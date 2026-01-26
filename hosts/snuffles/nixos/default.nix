# Snuffles specific NixOS configuration (ADS-B feeder with RTL-SDR)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos
    ../../../modules/nixos/laptop.nix
  ];

  # PiAware feeder ID secret
  sops.secrets.piaware-feeder-id = {
    sopsFile = "${inputs.self}/secrets/piaware.yaml";
    key = hostname;
  };

  # FR24 sharing key secret
  sops.secrets.fr24feed-key = {
    sopsFile = "${inputs.self}/secrets/fr24feed.yaml";
    key = hostname;
  };

  # Host-specific networking
  networking.hostName = "snuffles";

  # RTL-SDR udev rules
  hardware.rtl-sdr.enable = true;

  # Load RTL-SDR module and blacklist DVB driver
  boot.kernelModules = [ "rtl_sdr" ];
  boot.blacklistedKernelModules = [ "dvb_usb_rtl28xxu" "rtl2832" "rtl2830" ];

  # ADS-B packages
  environment.systemPackages = with pkgs; [
    readsb
    dump1090-fa
    rtl-sdr
  ];

  # Prevent dump1090 from auto-starting (we use readsb instead)
  systemd.services.dump1090-fa.enable = false;

  # Readsb service for RTL-SDR
  systemd.services.readsb = {
    description = "Readsb ADS-B decoder";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = ''
        ${pkgs.readsb}/bin/readsb \
          --device-type rtlsdr \
          --gain -10 \
          --ppm 0 \
          --net \
          --net-bind-address 0.0.0.0 \
          --net-heartbeat 60 \
          --net-ro-size 1250 \
          --net-ro-interval 0.05 \
          --net-ri-port 30001 \
          --net-ro-port 30002 \
          --net-sbs-port 30003 \
          --net-bi-port 30004,30104 \
          --net-bo-port 30005 \
          --net-beast-reduce-interval 0.5 \
          --net-beast-reduce-out-port 30006 \
          --json-location-accuracy 2 \
          --write-json /run/readsb \
          --write-json-every 1
      '';
      Restart = "always";
      RestartSec = "5";
      RuntimeDirectory = "readsb";
    };
  };

  # Enable podman for containers
  virtualisation.podman = {
    enable = true;
    dockerCompat = true;
  };

  # PiAware container (FlightAware feeder)
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
      ExecStart = pkgs.writeShellScript "start-piaware" ''
        FEEDER_ID=$(cat ${config.sops.secrets.piaware-feeder-id.path})
        ${pkgs.podman}/bin/podman run --rm --name piaware \
          -e BEASTHOST=host.containers.internal \
          -e BEASTPORT=30005 \
          -e FEEDER_ID="$FEEDER_ID" \
          -v /var/lib/piaware:/var/cache/piaware \
          --add-host=host.containers.internal:host-gateway \
          ghcr.io/sdr-enthusiasts/docker-piaware:latest
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 piaware";
    };
  };

  # FR24 Feed container (Flightradar24 feeder)
  # To register a new feeder, use:
  # curl "http://feed.flightradar24.com/self-service.php?action=register&latitude=LAT&longitude=LON&altitude=ALT_IN_FEET&email=EMAIL&feed_type=adsb&sw=1.0.54-0"
  # Radar ID: T-LEGT56
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
      ExecStart = pkgs.writeShellScript "start-fr24feed" ''
        FR24KEY=$(cat ${config.sops.secrets.fr24feed-key.path})
        ${pkgs.podman}/bin/podman run --rm --name fr24feed \
          -e BEASTHOST=host.containers.internal \
          -e BEASTPORT=30005 \
          -e FR24KEY="$FR24KEY" \
          -e FR24USER=fr24@fjim.fastmail.jp \
          -e MLAT=yes \
          -e LAT=40.2444 \
          -e LON=-3.6971 \
          -v /var/lib/fr24feed:/etc/fr24feed \
          --add-host=host.containers.internal:host-gateway \
          ghcr.io/sdr-enthusiasts/docker-flightradar24:latest
      '';
      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 fr24feed";
    };
  };

  # Create persistent directories for feeders
  systemd.tmpfiles.rules = [
    "d /var/lib/piaware 0755 root root -"
    "d /var/lib/fr24feed 0755 root root -"
  ];


  # Open firewall for ADS-B ports
  networking.firewall.allowedTCPPorts = [
    30001 30002 30003 30004 30005 30006  # readsb Beast/SBS ports
    30104  # Additional Beast input
    8080   # tar1090 web interface (if added)
  ];

  # System state version
  system.stateVersion = lib.mkForce "25.11";
}
