{ config, lib, pkgs, inputs, ... }:

with lib;

let
  cfg = config.services.openwebrx;
in {
  options.services.openwebrx = {
    enable = mkEnableOption "OpenWebRX+ service";
    
    port = mkOption {
      type = types.port;
      default = 8073;
      description = "Port to expose OpenWebRX+ web interface";
    };

    adminUser = mkOption {
      type = types.str;
      default = "admin";
      description = "Admin username";
    };
  };

  config = mkIf cfg.enable {
    # OpenWebRX+ requires RTL-SDR hardware support
    hardware.rtl-sdr.enable = true;
    boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

    sops.secrets.openwebrx_admin_password = {
      sopsFile = "${inputs.self}/secrets/openwebrx.yaml";
      key = "admin_password";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/openwebrx 0755 root root -"
    ];

    systemd.services.openwebrx = {
      description = "OpenWebRX+ Container";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f openwebrx";
        ExecStart = pkgs.writeShellScript "start-openwebrx" ''
          ADMIN_PASS=$(cat ${config.sops.secrets.openwebrx_admin_password.path})
          ${pkgs.podman}/bin/podman run --rm --name openwebrx \
            --privileged \
            -p ${toString cfg.port}:8073 \
            -e OPENWEBRX_ADMIN_USER=${cfg.adminUser} \
            -e OPENWEBRX_ADMIN_PASSWORD="$ADMIN_PASS" \
            -e TZ=Europe/Madrid \
            -v /var/lib/openwebrx/etc:/etc/openwebrx \
            -v /var/lib/openwebrx/var:/var/lib/openwebrx \
            -v /dev/bus/usb:/dev/bus/usb \
            slechev/openwebrxplus-softmbe:latest
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 openwebrx";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
