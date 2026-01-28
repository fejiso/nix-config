# ADS-B Readsb decoder module
# Supports multiple SDR types (rtlsdr, airspy, etc.)
# Provides Beast protocol output on standard ports for feeders
{ config, lib, pkgs, ... }:

with lib;

{
  options.services.adsb-readsb = {
    enable = mkEnableOption "Readsb ADS-B decoder";

    deviceType = mkOption {
      type = types.enum [ "rtlsdr" "airspy" "sdr-ifile" "modesbeast" ];
      default = "rtlsdr";
      description = "SDR device type to use";
    };

    gain = mkOption {
      type = types.str;
      default = "-10";
      description = "Gain setting (-10 for auto gain)";
    };

    ppm = mkOption {
      type = types.int;
      default = 0;
      description = "PPM correction value";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "Additional arguments to pass to readsb";
    };

    enableRtlSdrHardware = mkOption {
      type = types.bool;
      default = true;
      description = "Enable RTL-SDR hardware support (udev rules, kernel modules)";
    };

    tar1090 = {
      enable = mkEnableOption "tar1090 web interface";

      port = mkOption {
        type = types.port;
        default = 8080;
        description = "Port for tar1090 web interface";
      };

      latitude = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Latitude for map center (optional)";
      };

      longitude = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Longitude for map center (optional)";
      };
    };
  };

  config = mkIf config.services.adsb-readsb.enable {
    # RTL-SDR hardware support
    hardware.rtl-sdr.enable = mkIf config.services.adsb-readsb.enableRtlSdrHardware true;

    # Load RTL-SDR module and blacklist DVB driver
    boot.kernelModules = mkIf config.services.adsb-readsb.enableRtlSdrHardware [ "rtl_sdr" ];
    boot.blacklistedKernelModules = mkIf config.services.adsb-readsb.enableRtlSdrHardware [
      "dvb_usb_rtl28xxu"
      "rtl2832"
      "rtl2830"
    ];

    # Install readsb and SDR tools
    environment.systemPackages = with pkgs; [
      readsb
      rtl-sdr
    ];

    # Readsb service
    systemd.services.readsb = {
      description = "Readsb ADS-B decoder";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = let
          cfg = config.services.adsb-readsb;
          args = [
            "${pkgs.readsb}/bin/readsb"
            "--device-type ${cfg.deviceType}"
            "--gain ${cfg.gain}"
            "--ppm ${toString cfg.ppm}"
            "--net"
            "--net-bind-address 0.0.0.0"
            "--net-heartbeat 60"
            "--net-ro-size 1250"
            "--net-ro-interval 0.05"
            "--net-ri-port 30001"
            "--net-ro-port 30002"
            "--net-sbs-port 30003"
            "--net-bi-port 30004,30104"
            "--net-bo-port 30005"
            "--net-beast-reduce-interval 0.5"
            "--net-beast-reduce-out-port 30006"
            "--json-location-accuracy 2"
            "--write-json /run/readsb"
            "--write-json-every 1"
          ] ++ cfg.extraArgs;
        in concatStringsSep " \\\n  " args;
        Restart = "always";
        RestartSec = "5";
        RuntimeDirectory = "readsb";
      };
    };

    # Open firewall for ADS-B ports
    networking.firewall.allowedTCPPorts = [
      30001 30002 30003 30004 30005 30006  # readsb Beast/SBS ports
      30104  # Additional Beast input
    ] ++ optional config.services.adsb-readsb.tar1090.enable config.services.adsb-readsb.tar1090.port;

    # Enable podman for tar1090 container
    virtualisation.podman = mkIf config.services.adsb-readsb.tar1090.enable {
      enable = true;
      dockerCompat = true;
    };

    # tar1090 web interface
    systemd.services.tar1090 = mkIf config.services.adsb-readsb.tar1090.enable {
      description = "tar1090 ADS-B Web Interface";
      after = [ "network-online.target" "readsb.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.podman ];
      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f tar1090";
        ExecStart =
          let
            cfg = config.services.adsb-readsb.tar1090;
          in
          pkgs.writeShellScript "start-tar1090" ''
            ${pkgs.podman}/bin/podman run --rm --name tar1090 \
              -p ${toString cfg.port}:80 \
              -e BEASTHOST=host.containers.internal \
              -e BEASTPORT=30005 \
              ${optionalString (cfg.latitude != null) "-e LAT=${cfg.latitude}"} \
              ${optionalString (cfg.longitude != null) "-e LONG=${cfg.longitude}"} \
              --add-host=host.containers.internal:host-gateway \
              ghcr.io/sdr-enthusiasts/docker-tar1090:latest
          '';
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 tar1090";
      };
    };
  };
}
