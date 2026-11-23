{ ... }: {
  # Turnkey zero-chicken-and-egg host provisioning & key enrollment apps:
  #
  #   nix run .#bootstrap-host -- <hostname> <live-ip> [--no-reboot]
  #     1. Verifies SSH to root@<live-ip> and checks that the target disko block
  #        device exists and is NOT backing the Live USB itself (/iso).
  #     2. Generates fresh ssh_host_{ed25519,rsa}_key in /run/user/$UID (RAM,
  #        wiped on exit) and derives the host's age recipient.
  #     3. Enrolls <hostname> in nix-config-private/.sops.yaml + lib/build-keys.nix,
  #        runs `sops updatekeys -y` on that host's secret files, pushes `private`,
  #        and runs `nix flake update private` *before* building.
  #     4. Builds diskoScript + system toplevel once (secrets already match!).
  #     5. Formats/mounts /mnt via disko, injects the pre-generated SSH host keys
  #        into /mnt/etc/ssh, streams toplevel straight into /mnt (?remote-store=/mnt),
  #        runs nixos-install, prompts for `passwd z-247` ONLY if no declarative
  #        hashedPassword/hashedPasswordFile is configured, and reboots.
  #
  #   nix run .#enroll-host -- <hostname> <running-ip>
  #     Reads `/etc/ssh/ssh_host_ed25519_key.pub` from an *already-installed* host
  #     (without wiping or reinstalling anything) and registers it in `.sops.yaml`,
  #     `lib/build-keys.nix`, `sops updatekeys`, and `flake.lock`.
  perSystem = { pkgs, lib, ... }:
    let
      runtimePath = lib.makeBinPath (with pkgs; [
        bash
        coreutils
        findutils
        gnugrep
        gnused
        gawk
        git
        jq
        openssh
        python3
        sops
        ssh-to-age
      ]);

      enrollHelper = ../scripts/enroll-host-keys.py;

      sharedHelpers = ''
        export PATH="${runtimePath}:$PATH"
        export NIX_CONFIG="experimental-features = nix-command flakes"

        resolve_repos() {
          if [ -z "''${NIX_CONFIG_DIR:-}" ]; then
            if [ -f "$PWD/flake.nix" ] && [ -f "$PWD/lib/build-keys.nix" ]; then
              NIX_CONFIG_DIR="$PWD"
            else
              NIX_CONFIG_DIR="/home/z-247/dev/nix-config"
            fi
          fi
          if [ -z "''${NIX_PRIVATE_DIR:-}" ]; then
            candidate="$(dirname "$NIX_CONFIG_DIR")/nix-config-private"
            if [ -d "$candidate" ]; then
              NIX_PRIVATE_DIR="$candidate"
            else
              NIX_PRIVATE_DIR="/home/z-247/dev/nix-config-private"
            fi
          fi
          if [ ! -f "$NIX_CONFIG_DIR/flake.nix" ]; then
            echo "ERROR: nix-config checkout not found at $NIX_CONFIG_DIR (set NIX_CONFIG_DIR)" >&2
            exit 1
          fi
          if [ ! -f "$NIX_PRIVATE_DIR/.sops.yaml" ]; then
            echo "ERROR: nix-config-private checkout not found at $NIX_PRIVATE_DIR (set NIX_PRIVATE_DIR)" >&2
            exit 1
          fi
        }

        enroll_keys_and_update_flake() {
          local host="$1"
          local ssh_pub="$2"
          local age_pub="$3"

          echo "==> Enrolling $host in $NIX_PRIVATE_DIR/.sops.yaml & $NIX_CONFIG_DIR/lib/build-keys.nix"
          python3 "${enrollHelper}" \
            "$host" "$ssh_pub" "$age_pub" \
            "$NIX_PRIVATE_DIR/.sops.yaml" \
            "$NIX_CONFIG_DIR/lib/build-keys.nix"

          echo "==> Discovering sops secret files used by nixosConfigurations.$host"
          mapfile -t secret_files < <(
            nix eval --json "$NIX_CONFIG_DIR#nixosConfigurations.''${host}.config.sops.secrets" \
              --apply 's: builtins.attrValues (builtins.mapAttrs (_: v: baseNameOf (toString v.sopsFile)) s)' \
              | jq -r 'unique | .[]'
          )

          (
            cd "$NIX_PRIVATE_DIR"
            # Prefer passphrase-less age key (~/.config/sops/age/keys.txt) when present
            # so sops doesn't prompt for the SSH key passphrase on every file.
            if [ -r "''${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}" ]; then
              export SOPS_AGE_SSH_PRIVATE_KEY_FILE=/dev/null
            fi
            for sf in "''${secret_files[@]}"; do
              if [ -f "secrets/$sf" ]; then
                echo "    sops updatekeys -y secrets/$sf"
                sops updatekeys -y "secrets/$sf"
              fi
            done

            if [ -n "$(git status --porcelain -- .sops.yaml secrets/)" ]; then
              git add .sops.yaml secrets/
              git commit -m "Enroll $host age/ssh host keys"
              git push
            else
              echo "    nix-config-private already up to date for $host"
            fi
          )

          echo "==> Updating flake input 'private' in $NIX_CONFIG_DIR"
          (
            cd "$NIX_CONFIG_DIR"
            nix flake update private
            git add flake.lock lib/build-keys.nix
          )
        }
      '';

      bootstrapScript = pkgs.writeShellScript "bootstrap-host" ''
        set -euo pipefail
        ${sharedHelpers}

        DO_REBOOT=1
        POSITIONAL=()
        for arg in "$@"; do
          case "$arg" in
            --no-reboot) DO_REBOOT=0 ;;
            -h|--help)
              echo "Usage: nix run .#bootstrap-host -- <hostname> <live-ip> [--no-reboot]"
              exit 0
              ;;
            *) POSITIONAL+=("$arg") ;;
          esac
        done

        if [ "''${#POSITIONAL[@]}" -ne 2 ]; then
          echo "Usage: nix run .#bootstrap-host -- <hostname> <live-ip> [--no-reboot]" >&2
          exit 1
        fi

        HOST="''${POSITIONAL[0]}"
        RAW_IP="''${POSITIONAL[1]#root@}"
        LIVE="root@''${RAW_IP}"

        resolve_repos

        echo "==> Checking nixosConfigurations.$HOST target disk"
        TARGET_DISK=$(nix eval --raw "$NIX_CONFIG_DIR#nixosConfigurations.''${HOST}.config.disko.devices.disk.main.device")
        echo "    Configured target disk: $TARGET_DISK"

        echo "==> Preparing SSH access to Live USB ($LIVE)"
        if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$LIVE" true 2>/dev/null; then
          ssh-keygen -R "$RAW_IP" >/dev/null 2>&1 || true
          if ! ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=5 "$LIVE" true 2>/dev/null; then
            ssh-copy-id -o StrictHostKeyChecking=accept-new "$LIVE"
          fi
        fi

        echo "==> Verifying $TARGET_DISK & loading btrfs/dm_crypt on $LIVE"
        ssh -o StrictHostKeyChecking=accept-new "$LIVE" "
          set -euo pipefail
          export PATH=/run/wrappers/bin:/run/current-system/sw/bin:\''${PATH:-/usr/bin:/bin}
          if [ -d /run/booted-system/kernel-modules ]; then
            export MODULE_DIR=/run/booted-system/kernel-modules/lib/modules
            modprobe -d /run/booted-system/kernel-modules btrfs dm_crypt vfat loop || true
          else
            modprobe btrfs dm_crypt vfat loop || true
          fi
          echo \"    Live USB kernel: \$(uname -r)\"
          if ! grep -qw btrfs /proc/filesystems; then
            echo 'ERROR: btrfs is still not in /proc/filesystems on Live USB!' >&2
            dmesg | tail -n 15 >&2 || true
            exit 1
          fi
          lsblk -d -o NAME,SIZE,MODEL,TRAN
          if [ ! -b '$TARGET_DISK' ]; then
            echo 'ERROR: Target block device $TARGET_DISK does not exist on Live USB!' >&2
            exit 1
          fi
          target_real=\$(readlink -f '$TARGET_DISK')
          for mp in /iso /nix/.ro-store; do
            src=\$(awk -v m=\"\$mp\" '\$2 == m {print \$1}' /proc/mounts | head -n1)
            if [ -n \"\$src\" ]; then
              src_real=\$(readlink -f \"\$src\" 2>/dev/null || echo \"\$src\")
              case \"\$src_real\" in
                \"\$target_real\"*)
                  echo \"ABORT: $TARGET_DISK backs \$mp (\$src_real) — refusing to wipe Live USB!\" >&2
                  exit 1
                  ;;
              esac
            fi
          done
        "

        RUN_BASE="/run/user/$(id -u)"
        if [ ! -d "$RUN_BASE" ]; then
          RUN_BASE="/tmp"
        fi
        WORKDIR=$(mktemp -d "$RUN_BASE/bootstrap-''${HOST}.XXXXXX")
        chmod 0700 "$WORKDIR"
        trap 'rm -rf "$WORKDIR"' EXIT

        echo "==> Generating fresh SSH host keys for $HOST in RAM ($WORKDIR)"
        ssh-keygen -q -t ed25519 -N "" -C "root@$HOST" -f "$WORKDIR/ssh_host_ed25519_key"
        ssh-keygen -q -t rsa -b 4096 -N "" -C "root@$HOST" -f "$WORKDIR/ssh_host_rsa_key"
        SSH_PUB=$(cat "$WORKDIR/ssh_host_ed25519_key.pub")
        AGE_PUB=$(ssh-to-age < "$WORKDIR/ssh_host_ed25519_key.pub")
        echo "    SSH: $SSH_PUB"
        echo "    Age: $AGE_PUB"

        enroll_keys_and_update_flake "$HOST" "$SSH_PUB" "$AGE_PUB"

        echo "==> Building diskoScript and system closure for $HOST"
        DISKO=$(nix build "$NIX_CONFIG_DIR#nixosConfigurations.''${HOST}.config.system.build.diskoScript" --no-link --print-out-paths)
        TOPLEVEL=$(nix build "$NIX_CONFIG_DIR#nixosConfigurations.''${HOST}.config.system.build.toplevel" --no-link --print-out-paths)
        echo "    DISKO=$DISKO"
        echo "    TOPLEVEL=$TOPLEVEL"

        echo "==> Freeing any temporary RAM store paths on $LIVE and running disko"
        ssh "$LIVE" "export PATH=/run/wrappers/bin:/run/current-system/sw/bin:\$PATH; nix-collect-garbage >/dev/null 2>&1 || true"
        nix copy --to "ssh://$LIVE" "$DISKO"
        ssh -t "$LIVE" "export MODULE_DIR=/run/booted-system/kernel-modules/lib/modules; $DISKO" || {
          echo "ERROR: disko failed — last 20 lines of Live USB dmesg:" >&2
          ssh "$LIVE" "dmesg | tail -n 20" >&2 || true
          exit 1
        }

        echo "==> Injecting pre-enrolled SSH host keys into /mnt/etc/ssh"
        ssh "$LIVE" "install -d -m 0755 /mnt/etc/ssh"
        scp -q "$WORKDIR"/ssh_host_* "$LIVE:/mnt/etc/ssh/"
        ssh "$LIVE" "chmod 0600 /mnt/etc/ssh/ssh_host_*_key && chmod 0644 /mnt/etc/ssh/ssh_host_*_key.pub && chown root:root /mnt/etc/ssh/ssh_host_*"

        echo "==> Streaming system closure directly onto /mnt/nix/store"
        nix copy --no-check-sigs --to "ssh-ng://$LIVE?remote-store=/mnt" "$TOPLEVEL"

        echo "==> Running nixos-install on /mnt"
        ssh -t "$LIVE" "nixos-install --no-root-passwd --root /mnt --system $TOPLEVEL"

        HAS_DECL_PW=$(nix eval --raw "$NIX_CONFIG_DIR#nixosConfigurations.''${HOST}.config.users.users.z-247" \
          --apply 'u: if (u.hashedPassword or null) != null || (u.hashedPasswordFile or null) != null then "1" else "0"')
        if [ "$HAS_DECL_PW" = "1" ]; then
          echo "==> Declarative password hash configured for z-247 — skipping interactive passwd."
        else
          echo "==> No declarative password hash set for z-247 — enter local login password for z-247:"
          ssh -t "$LIVE" "nixos-enter --root /mnt -c '/nix/var/nix/profiles/system/sw/bin/passwd z-247'"
        fi

        if [ "$DO_REBOOT" = "1" ]; then
          echo "==> Rebooting $HOST into installed system"
          ssh "$LIVE" "reboot" || true
        else
          echo "==> Done (--no-reboot specified; /mnt remains mounted on $LIVE)"
        fi
      '';

      enrollScript = pkgs.writeShellScript "enroll-host" ''
        set -euo pipefail
        ${sharedHelpers}

        if [ "$#" -ne 2 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
          echo "Usage: nix run .#enroll-host -- <hostname> <running-ip-or-host>" >&2
          exit 1
        fi

        HOST="$1"
        TARGET="root@''${2#root@}"

        resolve_repos

        echo "==> Fetching existing /etc/ssh/ssh_host_ed25519_key.pub from $TARGET"
        SSH_PUB=$(ssh -o StrictHostKeyChecking=accept-new "$TARGET" "cat /etc/ssh/ssh_host_ed25519_key.pub")
        AGE_PUB=$(printf '%s\n' "$SSH_PUB" | ssh-to-age)
        echo "    SSH: $SSH_PUB"
        echo "    Age: $AGE_PUB"

        enroll_keys_and_update_flake "$HOST" "$SSH_PUB" "$AGE_PUB"
        echo "==> Done! $HOST is enrolled in sops & build-keys.nix."
      '';
    in
    {
      apps = {
        bootstrap-host = {
          type = "app";
          program = toString bootstrapScript;
        };
        enroll-host = {
          type = "app";
          program = toString enrollScript;
        };
      };
    };
}
