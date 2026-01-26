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
  virtualisation.oci-containers.containers.piaware = {
    image = "ghcr.io/sdr-enthusiasts/docker-piaware:latest";
    environment = {
      BEASTHOST = "host.containers.internal";
      BEASTPORT = "30005";
    };
    volumes = [ "/var/lib/piaware:/var/cache/piaware" ];
  };

  # FR24 Feed container (Flightradar24 feeder)
  virtualisation.oci-containers.containers.fr24feed = {
    image = "ghcr.io/sdr-enthusiasts/docker-flightradar24:latest";
    environment = {
      BEASTHOST = "host.containers.internal";
      BEASTPORT = "30005";
      FR24KEY = "b7496861b5f2137f";
      MLAT = "yes";
    };
    volumes = [ "/var/lib/fr24feed:/etc/fr24feed" ];
  };

  # Create persistent directories for feeders
  systemd.tmpfiles.rules = [
    "d /var/lib/piaware 0755 root root -"
    "d /var/lib/fr24feed 0755 root root -"
  ];

  # Ensure feeders start after readsb and have enough file descriptors
  systemd.services.podman-fr24feed = {
    after = [ "readsb.service" ];
    serviceConfig.LimitNOFILE = 65535;
  };
  systemd.services.podman-piaware = {
    after = [ "readsb.service" ];
    serviceConfig.LimitNOFILE = 65535;
  };

  # Open firewall for ADS-B ports
  networking.firewall.allowedTCPPorts = [
    30001 30002 30003 30004 30005 30006  # readsb Beast/SBS ports
    30104  # Additional Beast input
    8080   # tar1090 web interface (if added)
  ];

  # System state version
  system.stateVersion = lib.mkForce "25.11";
}
