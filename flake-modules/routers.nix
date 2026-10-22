# OpenWrt router fleet managed with openwrt-nix/nuci.
#
# All router data (UCI models, topology registry, docs) lives in the PRIVATE
# flake input (nix-config-private) — infrastructure details are not public:
#   <private>/routers/registry.nix   — name → mgmt IP attrset
#   <private>/routers/common.nix     — shared fleet config + sops wiring
#   <private>/routers/<name>.nix     — per-router UCI transcription
#   <private>/docs/ROUTERS.md        — full documentation
#
# Per router <name>:
#   packages.router-<name>-json  — compiled uci.json (nix build, placeholders intact)
#   apps.diff-<name>             — read-only nuci diff against the live router
#   apps.deploy-<name>           — nuci deploy (watchdog + rollback safety net)
#
# Secrets are decrypted by nuci at compile/diff/deploy time from sops files in
# the private input (routers/common.nix), using the user age key.
{
  inputs,
  lib,
  ...
}:
let
  routerDir = "${inputs.private}/routers";
  routers = import "${routerDir}/registry.nix";
in
{
  perSystem =
    { pkgs, ... }:
    let
      uci = pkgs.callPackage "${inputs.openwrt-nix}/nix" { openwrt-imagebuilder = null; };

      mkRouter =
        name: target:
        uci.writeUci {
          imports = [
            "${routerDir}/common.nix"
            "${routerDir}/${name}.nix"
          ];
          _module.args = { inherit inputs; };
        };

      mkApp =
        verb: name: target: cfg:
        let
          targetArg =
            if target != null then
              ''TARGET="root@${target}"; [ $# -ge 1 ] && [ "''${1#-}" = "$1" ] && TARGET="$1" && shift''
            else
              ''TARGET="''${1:?usage: ${verb}-${name} root@<ip> [nuci flags]}"; shift'';
          watchdog = lib.optionalString (verb == "deploy") "--watchdog-timeout 120";
          confirm = lib.optionalString (verb == "deploy") ''
            # Show the read-only diff first, then ask for confirmation.
            # -y/--yes skips the prompt (for scripts/headless use).
            SKIP=0
            args=()
            for a in "$@"; do
              if [ "$a" = "-y" ] || [ "$a" = "--yes" ]; then SKIP=1; else args+=("$a"); fi
            done
            set -- "''${args[@]}"
            if [ "$SKIP" != 1 ]; then
              ${uci.nuci}/bin/nuci diff ${cfg.json} --target "$TARGET" || true
              printf '\nDeploy to %s? [y/N] ' "$TARGET"
              read -r ans < /dev/tty || { echo "no tty; aborting"; exit 1; }
              case "$ans" in y|Y|yes) ;; *) echo aborted; exit 1 ;; esac
            fi'';
        in
        {
          name = "${verb}-${name}";
          value = {
            type = "app";
            program = toString (
              pkgs.writeShellScript "${verb}-${name}" ''
                set -euo pipefail
                export PATH="${lib.makeBinPath [ pkgs.openssh pkgs.sops pkgs.age ]}:$PATH"
                ${targetArg}
                ${confirm}
                exec ${uci.nuci}/bin/nuci ${verb} ${cfg.json} --target "$TARGET" ${watchdog} "$@"
              ''
            );
          };
        };
    in
    {
      packages = (lib.mapAttrs' (
        name: _: lib.nameValuePair "router-${name}-json" (mkRouter name routers.${name}).json
      ) routers) // { inherit (uci) nuci; };

      apps = lib.listToAttrs (
        lib.concatMap (
          name:
          let
            cfg = mkRouter name routers.${name};
          in
          [
            (mkApp "diff" name routers.${name} cfg)
            (mkApp "deploy" name routers.${name} cfg)
          ]
        ) (lib.attrNames routers)
      );
    };
}
