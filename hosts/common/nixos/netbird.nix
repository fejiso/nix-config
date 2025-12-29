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
}
