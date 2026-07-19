{ config, ... }: {
  flake.modules.nixos.cli = { inputs, outputs, hostname, pkgs, lib, ... }: {
    home-manager = {
      useGlobalPkgs = false;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs outputs hostname; };

      backupFileExtension = "hm-backup";

      users.z-247 = { ... }: {
        # The home CLASS (cli / cli-full / linux-default) is chosen per host via
        # mk-host's `homeModules`, no longer forced here. Only the optional
        # per-host home dir is wired in, guarded so hosts without one (e.g.
        # z-turn) don't break.
        imports = lib.optional
          (builtins.pathExists "${inputs.self}/hosts/${hostname}/home")
          "${inputs.self}/hosts/${hostname}/home";

        # Import nixpkgs-unstable with the SAME platform shape as the system: a
        # cross set on cross hosts (e.g. armv7l z-turn), native otherwise. A plain
        # `system = hostPlatform.system` would build the home as a *native* target
        # set, so build-time tools (pandoc for eza's manpages → GHC) resolve to
        # the target arch and fail to bootstrap. Native hosts (build == host) get
        # the identical `localSystem`-only set as before, so no rebuild for them.
        _module.args.pkgs = lib.mkForce (import inputs.nixpkgs-unstable (
          {
            config = {
              allowUnfree = true;
              permittedInsecurePackages = [
                "electron-39.8.10"
              ];
            };
            overlays = [
              outputs.overlays.additions
              outputs.overlays.modifications
              outputs.overlays.unstable-packages
            ] ++ lib.optional (pkgs.stdenv.buildPlatform != pkgs.stdenv.hostPlatform)
              # systemd's bpf-framework (withLibBPF defaults to on for aarch)
              # fails to cross-compile: the `clang -target bpf` skeleton build
              # isn't given kernel/libc headers ('linux/types.h' not found).
              # HM only needs systemd for `systemctl --user`, so drop BPF in
              # the cross set (kr260 aarch64 / z-turn armv7l). The system's
              # own systemd (26.05) is untouched.
              (_final: prev: {
                systemd = prev.systemd.override { withLibBPF = false; };
              });
          }
          // (
            if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform
            then { localSystem = pkgs.stdenv.hostPlatform.system; }
            else {
              localSystem = pkgs.stdenv.buildPlatform.system;
              crossSystem = pkgs.stdenv.hostPlatform.system;
            }
          )
        ));
      };
    };
  };
}
