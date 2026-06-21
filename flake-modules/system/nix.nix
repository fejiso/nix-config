{ ... }: {
  flake.modules.nixos.cli =
# Nix configuration
{
  inputs,
  lib,
  config,
  pkgs,
  ...
}: {
  nix = let
    flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
  in {
    settings = {
      # Enable flakes and new 'nix' command
      experimental-features = "nix-command flakes";
      # Opinionated: disable global registry
      flake-registry = "";
      # Workaround for https://github.com/NixOS/nix/issues/9574
      nix-path = config.nix.nixPath;
      # Enable auto-optimise-store
      auto-optimise-store = true;
      # Trusted users for binary cache
      trusted-users = ["root" "@wheel"];
    };
    
    # Enable channels
    channel.enable = true;

    # Opinionated: make flake registry and nix path match flake inputs
    registry = lib.mapAttrs (_: flake: {inherit flake;}) flakeInputs;
    nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
    
  };

  # Garbage collection - system + user profiles
  systemd.services.nix-garbage-collect = {
    description = "Nix Garbage Collection (system + user)";
    serviceConfig.Type = "oneshot";
    path = [ config.nix.package pkgs.coreutils ];
    script = ''
      echo "=== Nix GC start ==="
      echo "Store size before: $(du -sh /nix/store | cut -f1)"

      # Delete old generations from all system profiles
      nix-collect-garbage --delete-older-than 7d

      # Delete old per-user profile generations (home-manager, nix-env)
      for dir in /nix/var/nix/profiles/per-user/*/; do
        [ -d "$dir" ] || continue
        for profile in "$dir"*; do
          # Skip if it's a generation link (handled by nix-collect-garbage)
          # Target actual profile heads like 'profile', 'home-manager', 'channels'
          [ -L "$profile" ] || continue
          case "$(basename "$profile")" in
            *-*-link) continue ;;  # skip generation links
          esac
          echo "Cleaning profile: $profile"
          nix-env --delete-generations +3 --profile "$profile" 2>/dev/null || true
        done
      done

      # Delete old home-manager generations stored in user home dirs
      for gcroot_dir in /home/*/.local/state/home-manager/gcroots; do
        [ -d "$gcroot_dir" ] || continue
        echo "Cleaning home-manager gcroots in: $gcroot_dir"
        find "$gcroot_dir" -maxdepth 1 -type l ! -name current-home -delete 2>/dev/null || true
      done

      echo "Store size after: $(du -sh /nix/store | cut -f1)"
      echo "=== Nix GC done ==="
    '';
  };

  systemd.timers.nix-garbage-collect = {
    description = "Nix Garbage Collection Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "weekly";
      Persistent = true;
      RandomizedDelaySec = "30min";
    };
  };

  # Allow unfree packages
  nixpkgs.config.allowUnfree = true;
}
;
}
