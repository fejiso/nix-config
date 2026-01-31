# Common Podman configuration and auto-update service
{ config, lib, pkgs, ... }:

{
  # Enable Podman auto-update for rootless containers across all users
  systemd.timers.podman-auto-update = {
    description = "Daily container image updates using podman auto-update";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update = {
    description = "Update container images and restart if needed";
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      # Update root containers
      echo "Checking containers for user root"
      ${pkgs.podman}/bin/podman auto-update || true

      # Update containers for all users with XDG_RUNTIME_DIR (rootless)
      for runtime_dir in /run/user/*; do
        if [ -d "$runtime_dir" ]; then
          uid=$(basename "$runtime_dir")
          username=$(id -un "$uid" 2>/dev/null) || continue
          echo "Checking containers for user $username (UID $uid)"
          # Run podman auto-update as the user
          # Note: We use systemd-run or sudo depending on what's available/appropriate
          # but the butthead config used sudo -u.
          sudo -u "$username" XDG_RUNTIME_DIR="$runtime_dir" ${pkgs.podman}/bin/podman auto-update || true
        fi
      done
    '';
  };
}
