# PhantomSDR-Plus (NovaSDR) service
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.phantomsdr-plus;
  
  # Configuration directory on host
  dataDir = "/var/lib/phantomsdr-plus";
in {
  options.services.phantomsdr-plus = {
    enable = mkEnableOption "PhantomSDR-Plus (NovaSDR) service";
    
    port = mkOption {
      type = types.port;
      default = 9002;
      description = "Port to expose PhantomSDR-Plus web interface";
    };

    repoUrl = mkOption {
      type = types.str;
      default = "https://github.com/Steven9101/NovaSDR.git";
      description = "Git repository URL for PhantomSDR-Plus (NovaSDR)";
    };
  };

  config = mkIf cfg.enable {
    # Required for RTL-SDR
    hardware.rtl-sdr.enable = true;
    boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" ];

    virtualisation.podman = {
      enable = true;
      dockerCompat = true;
    };

    systemd.tmpfiles.rules = [
      "d ${dataDir} 0755 root root -"
      "d ${dataDir}/config 0755 root root -"
      "d ${dataDir}/logs 0755 root root -"
      "d ${dataDir}/data 0755 root root -"
    ];

    # Service to build the image from source
    systemd.services.phantomsdr-plus-build = {
      description = "Build PhantomSDR-Plus (NovaSDR) Docker Image";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman pkgs.git pkgs.gnutar pkgs.gzip ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = dataDir;
      };
      script = ''
        if [ ! -d "source" ]; then
          git clone ${cfg.repoUrl} source
        else
          cd source
          git pull
          cd ..
        fi
        
        cd source
        ${pkgs.podman}/bin/podman build -t localhost/phantomsdr-plus:latest .
      '';
    };

    # PhantomSDR-Plus service
    systemd.services.phantomsdr-plus = {
      description = "PhantomSDR-Plus (NovaSDR) Container";
      after = [ "network-online.target" "phantomsdr-plus-build.service" ];
      wants = [ "network-online.target" ];
      requires = [ "phantomsdr-plus-build.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f phantomsdr-plus";
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --rm --name phantomsdr-plus \
            --privileged \
            --label io.containers.autoupdate=registry \
            -p ${toString cfg.port}:9002 \
            -v ${dataDir}/config:/app/config \
            -v ${dataDir}/logs:/app/logs \
            -v ${dataDir}/data:/app/data \
            -v /dev/bus/usb:/dev/bus/usb \
            -e TZ=Europe/Madrid \
            localhost/phantomsdr-plus:latest
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 phantomsdr-plus";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
