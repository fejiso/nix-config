# ADS-B feeders module (PiAware, FR24Feed)
# Runs feeder containers that send ADS-B data to tracking services
# Requires readsb or another Beast protocol source
{ config, lib, pkgs, hostname, inputs, ... }:

with lib;

{
  options.services.adsb-feeders = {
    piaware = {
      enable = mkEnableOption "PiAware FlightAware feeder";

      feederIdSecretFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "Path to file containing PiAware feeder ID (optional)";
      };
    };

    fr24feed = {
      enable = mkEnableOption "FlightRadar24 feeder";

      email = mkOption {
        type = types.str;
        description = "Email address for FR24 registration";
      };

      latitude = mkOption {
        type = types.str;
        description = "Antenna latitude (DD.DDDD format)";
      };

      longitude = mkOption {
        type = types.str;
        description = "Antenna longitude (DDD.DDDD format)";
      };

      sharingKeySecretFile = mkOption {
        type = types.path;
        description = "Path to file containing FR24 sharing key";
      };

      mlat = mkOption {
        type = types.bool;
        default = true;
        description = "Enable MLAT (multilateration)";
      };
    };

    adsbfi = {
      enable = mkEnableOption "adsb.fi feeder";

      uuidSecretFile = mkOption {
        type = types.path;
        description = "Path to file containing adsb.fi UUID";
      };
      
      mlat = mkOption {
        type = types.bool;
        default = true;
        description = "Enable MLAT";
      };

      latitude = mkOption {
        type = types.str;
        description = "Antenna latitude (DD.DDDD format)";
      };

      longitude = mkOption {
        type = types.str;
        description = "Antenna longitude (DDD.DDDD format)";
      };

      altitude = mkOption {
        type = types.str;
        default = "0";
        description = "Antenna altitude in meters";
      };

      name = mkOption {
        type = types.str;
        default = "${hostname}";
        description = "Feeder name displayed on maps";
      };

      webPort = mkOption {
        type = types.nullOr types.port;
        default = null;
        description = "Port to expose the internal tar1090 web interface";
      };
    };

    beastHost = mkOption {
      type = types.str;
      default = "host.containers.internal";
      description = "Beast protocol host for feeders";
    };

    beastPort = mkOption {
      type = types.str;
      default = "30005";
      description = "Beast protocol port for feeders";
    };
  };

  config = mkMerge [
    # Enable podman if any feeder is enabled
    (mkIf (config.services.adsb-feeders.piaware.enable || config.services.adsb-feeders.fr24feed.enable || config.services.adsb-feeders.adsbfi.enable) {
      virtualisation.podman = {
        enable = true;
        dockerCompat = true;
      };
    })

    # PiAware feeder
    (mkIf config.services.adsb-feeders.piaware.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/piaware 0755 root root -"
      ];

      systemd.services.piaware = {
        description = "PiAware FlightAware Feeder";
        after = [ "network-online.target" "readsb.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.podman ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "30";
          ExecStartPre = "-${pkgs.podman}/bin/podman rm -f piaware";
          ExecStart =
            let
              cfg = config.services.adsb-feeders;
            in
            pkgs.writeShellScript "start-piaware" ''
              ${if cfg.piaware.feederIdSecretFile != null then ''
                FEEDER_ID=$(cat ${cfg.piaware.feederIdSecretFile})
                ${pkgs.podman}/bin/podman run --rm --name piaware \
                  -e BEASTHOST=${cfg.beastHost} \
                  -e BEASTPORT=${cfg.beastPort} \
                  -e FEEDER_ID="$FEEDER_ID" \
                  -v /var/lib/piaware:/var/cache/piaware \
                  --add-host=host.containers.internal:host-gateway \
                  ghcr.io/sdr-enthusiasts/docker-piaware:latest
              '' else ''
                ${pkgs.podman}/bin/podman run --rm --name piaware \
                  -e BEASTHOST=${cfg.beastHost} \
                  -e BEASTPORT=${cfg.beastPort} \
                  -v /var/lib/piaware:/var/cache/piaware \
                  --add-host=host.containers.internal:host-gateway \
                  ghcr.io/sdr-enthusiasts/docker-piaware:latest
              ''}
            '';
          ExecStop = "${pkgs.podman}/bin/podman stop -t 10 piaware";
        };
      };
    })

    # FR24 Feed
    (mkIf config.services.adsb-feeders.fr24feed.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/fr24feed 0755 root root -"
      ];

      systemd.services.fr24feed = {
        description = "FR24 Feed FlightRadar24 Feeder";
        after = [ "network-online.target" "readsb.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.podman ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "30";
          ExecStartPre = "-${pkgs.podman}/bin/podman rm -f fr24feed";
          ExecStart =
            let
              cfg = config.services.adsb-feeders.fr24feed;
            in
            pkgs.writeShellScript "start-fr24feed" ''
              FR24KEY=$(cat ${cfg.sharingKeySecretFile})
              ${pkgs.podman}/bin/podman run --rm --name fr24feed \
                -e BEASTHOST=${config.services.adsb-feeders.beastHost} \
                -e BEASTPORT=${config.services.adsb-feeders.beastPort} \
                -e FR24KEY="$FR24KEY" \
                -e FR24USER=${cfg.email} \
                -e MLAT=${if cfg.mlat then "yes" else "no"} \
                -e LAT=${cfg.latitude} \
                -e LON=${cfg.longitude} \
                -v /var/lib/fr24feed:/etc/fr24feed \
                --add-host=host.containers.internal:host-gateway \
                ghcr.io/sdr-enthusiasts/docker-flightradar24:latest
            '';
          ExecStop = "${pkgs.podman}/bin/podman stop -t 10 fr24feed";
        };
      };
    })

    # adsb.fi Feeder
    (mkIf config.services.adsb-feeders.adsbfi.enable {
      systemd.tmpfiles.rules = [
        "d /var/lib/adsbfi 0755 root root -"
        "d /var/lib/graphs1090 0755 root root -"
      ];

      systemd.services.adsbfi = {
        description = "adsb.fi Feeder (Ultrafeeder)";
        after = [ "network-online.target" "readsb.service" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        path = [ pkgs.podman ];
        serviceConfig = {
          Type = "simple";
          Restart = "always";
          RestartSec = "30";
          ExecStartPre = "-${pkgs.podman}/bin/podman rm -f adsbfi";
          ExecStart =
            let
              cfg = config.services.adsb-feeders.adsbfi;
              beastHost = config.services.adsb-feeders.beastHost;
              beastPort = config.services.adsb-feeders.beastPort;
            in
            pkgs.writeShellScript "start-adsbfi" ''
              UUID=$(cat ${cfg.uuidSecretFile})
              # Ultrafeeder config for adsb.fi
              # We use ultrafeeder in 'net' mode to pull from local readsb
              
              ${pkgs.podman}/bin/podman run --rm --name adsbfi \
                ${optionalString (cfg.webPort != null) "-p ${toString cfg.webPort}:80"} \
                -e READSB_DEVICE_TYPE=none \
                -e READSB_NET_CONNECTOR=${beastHost},${beastPort},beast_in \
                -e ULTRAFEEDER_CONFIG="adsb,feed.adsb.fi,30004,beast_reduce_plus_out;mlat,feed.adsb.fi,31090" \
                -e UUID=$UUID \
                -e MLAT_USER=$UUID \
                -e LAT=${cfg.latitude} \
                -e LONG=${cfg.longitude} \
                -e ALT=${cfg.altitude} \
                -e FEEDER_NAME="${cfg.name}" \
                -v /var/lib/adsbfi:/var/globe_history \
                -v /var/lib/graphs1090:/var/lib/collectd \
                --add-host=host.containers.internal:host-gateway \
                ghcr.io/sdr-enthusiasts/docker-adsb-ultrafeeder:latest
            '';
          ExecStop = "${pkgs.podman}/bin/podman stop -t 10 adsbfi";
        };
      };
    })
  ];
}
