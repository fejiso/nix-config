{ ... }: {
  flake.modules.nixos.cli =
# Universal services (the mesh stack moved to mesh.nix; audio/avahi/cups/
# geoclue/timezone moved to desktop-services.nix).
{
  config,
  lib,
  pkgs,
  hostname,
  ...
}: {
  # SSH server
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "prohibit-password";
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      UseDns = false;
    };
  };

  # Plain in-memory SSH agent. gpg-agent's enableSshSupport is off because its
  # pinentry-curses prompt is unusable under niri/Wayland; ssh-add caches the
  # key in memory and prompts in the same terminal instead.
  programs.ssh.startAgent = true;

  # iperf3 server listening on wt0 interface for network performance testing
  systemd.services.iperf3-wt0 = {
    description = "iperf3 network performance server on wt0";
    after = [ "network-online.target" "sys-subsystem-net-devices-wt0.device" ];
    wants = [ "network-online.target" ];
    bindsTo = [ "sys-subsystem-net-devices-wt0.device" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.iproute2 pkgs.gawk ];
    script = ''
      IP=$(ip -4 addr show wt0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
      if [ -n "$IP" ]; then
        exec ${pkgs.iperf3}/bin/iperf3 -s -B "$IP"
      else
        echo "Could not get IP for wt0 interface"
        exit 1
      fi
    '';
    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10";
    };
  };

  # iperf3 port (only on wt0 via binding, but firewall needs to allow it)
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 5201 ];

  # Btrfs automatic scrubbing - safe no-op on non-btrfs hosts
  services.btrfs.autoScrub.enable = true;

}
;
}
