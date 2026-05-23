{ ... }: {
  flake.modules.nixos.default =
{
  config, pkgs, ...
}:

{
  services.netbird.enable = true;

  # Enable systemd-resolved for Netbird DNS
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
  };

  # Custom netbird setup service that uses the setup key
  systemd.services.netbird-setup = {
    description = "NetBird setup with encrypted key";
    after = [ "network-online.target" "sops-nix.service" "netbird.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      User = "root";
      ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.netbird}/bin/netbird up --setup-key \"$(cat ${config.sops.secrets.netbird-setup-key.path})\"'";
      ExecStop = "${pkgs.netbird}/bin/netbird down";
    };
  };

  # Restart netbird after system wakes from suspend
  systemd.services.netbird-resume = {
    description = "Restart NetBird after suspend/resume";
    after = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];
    wantedBy = [ "suspend.target" "hibernate.target" "hybrid-sleep.target" ];

    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl restart netbird.service";
    };
  };

  # Watchdog: restart netbird when DNS resolution is broken
  systemd.services.netbird-dns-watchdog = {
    description = "Restart NetBird if DNS resolution fails";
    after = [ "network-online.target" "netbird.service" ];
    wants = [ "network-online.target" ];

    serviceConfig = {
      Type = "oneshot";
    };

    script = ''
      if ! ${pkgs.host}/bin/host -W 5 cloudflare.com 127.0.0.53 > /dev/null 2>&1; then
        echo "DNS resolution failed, restarting netbird and flushing resolved"
        ${pkgs.systemd}/bin/systemctl restart netbird.service
        ${pkgs.systemd}/bin/resolvectl flush-caches
        ${pkgs.systemd}/bin/resolvectl reset-server-features
      fi
    '';
  };

  systemd.timers.netbird-dns-watchdog = {
    description = "Periodically check DNS for netbird health";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "5min";
      OnUnitActiveSec = "15min";
    };
  };
}
;
}
