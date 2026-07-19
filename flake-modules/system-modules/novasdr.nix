{ ... }: {
  flake.modules.nixos.novasdr =
# NovaSDR service
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.novasdr;
  
  # Configuration directory on host
  dataDir = "/var/lib/novasdr";
in {
  options.services.novasdr = {
    enable = mkEnableOption "NovaSDR service";
    
    port = mkOption {
      type = types.port;
      default = 9002;
      description = "Port to expose NovaSDR web interface";
    };

    repoUrl = mkOption {
      type = types.str;
      default = "https://github.com/Steven9101/NovaSDR.git";
      description = "Git repository URL for NovaSDR";
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
    systemd.services.novasdr-build = {
      description = "Build NovaSDR Docker Image";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman pkgs.git pkgs.gnutar pkgs.gzip pkgs.gnused pkgs.gnugrep ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        WorkingDirectory = dataDir;
      };
      script = ''
        if [ ! -d "source" ]; then
          git clone --recursive ${cfg.repoUrl} source
        else
          cd source
          # Discard the local opus patch below so `git pull` doesn't conflict.
          git checkout -- Dockerfile
          git pull
          git submodule update --init --recursive
          cd ..
        fi

        cd source
        # Upstream Dockerfile is missing opus: crates/interop/build.rs
        # hard-requires opus via pkg-config ("Couldn't find opus"), but the
        # image never installs it. Add libopus-dev (builder stage) and
        # libopus0 (runtime stage). Drop once fixed upstream.
        grep -q 'libopus-dev' Dockerfile || \
          sed -i 's/^\( *\)libusb-1\.0-0-dev/\1libopus-dev \\\n\1libusb-1.0-0-dev/' Dockerfile
        grep -q '^ *libopus0' Dockerfile || \
          sed -i 's/^\( *\)libusb-1\.0-0 /\1libopus0 \\\n\1libusb-1.0-0 /' Dockerfile

        ${pkgs.podman}/bin/podman build -t localhost/novasdr:latest .
      '';
    };

    # NovaSDR service
    systemd.services.novasdr = {
      description = "NovaSDR Container";
      after = [ "network-online.target" "novasdr-build.service" ];
      wants = [ "network-online.target" ];
      requires = [ "novasdr-build.service" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f novasdr";
        ExecStart = ''
          ${pkgs.podman}/bin/podman run --rm --name novasdr \
            --privileged \
            --label io.containers.autoupdate=registry \
            -p ${toString cfg.port}:9002 \
            -v ${dataDir}/config:/app/config \
            -v ${dataDir}/logs:/app/logs \
            -v ${dataDir}/data:/app/data \
            -v /dev/bus/usb:/dev/bus/usb \
            -e TZ=Europe/Madrid \
            localhost/novasdr:latest
        '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 novasdr";
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
};
}
