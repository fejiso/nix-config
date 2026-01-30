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
    ../../../modules/nixos/adsb-readsb.nix
    ../../../modules/nixos/adsb-feeders.nix
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

  # ADS-B Location secrets
  sops.secrets.adsb-lat = {
    sopsFile = "${inputs.self}/secrets/adsb-location.yaml";
    key = "${hostname}/latitude";
  };
  sops.secrets.adsb-lon = {
    sopsFile = "${inputs.self}/secrets/adsb-location.yaml";
    key = "${hostname}/longitude";
  };
  sops.secrets.adsb-alt = {
    sopsFile = "${inputs.self}/secrets/adsb-location.yaml";
    key = "${hostname}/altitude";
  };
  
  sops.secrets.adsb-uuid = {
    sopsFile = "${inputs.self}/secrets/adsbfi.yaml";
    key = "${hostname}";
  };

  # Host-specific networking
  networking.hostName = "snuffles";

  # ADS-B Readsb decoder with RTL-SDR
  services.adsb-readsb = {
    enable = false;
    deviceType = "rtlsdr";
    gain = "-10";  # Auto gain
    ppm = 0;
    
    tar1090.enable = false;
  };

  # ADS-B Feeders
  # FR24 registration: curl "http://feed.flightradar24.com/self-service.php?action=register&latitude=LAT&longitude=LON&altitude=ALT_IN_FEET&email=EMAIL&feed_type=adsb&sw=1.0.54-0"
  # Radar ID: T-LEGT56
  services.adsb-feeders = {
    piaware = {
      enable = true;
      feederIdSecretFile = config.sops.secrets.piaware-feeder-id.path;
    };

    fr24feed = {
      enable = true;
      email = "fr24@fjim.fastmail.jp";
      latitude = "40.2444";
      longitude = "-3.6971";
      sharingKeySecretFile = config.sops.secrets.fr24feed-key.path;
      mlat = true;
    };

    adsbfi = {
      enable = true;
      uuidSecretFile = config.sops.secrets.adsb-uuid.path;
      latitude = "$(cat ${config.sops.secrets.adsb-lat.path})";
      longitude = "$(cat ${config.sops.secrets.adsb-lon.path})";
      altitude = "$(cat ${config.sops.secrets.adsb-alt.path})";
      mlat = true;
      webPort = 8080;
      
      # Handle SDR decoding directly
      deviceType = "rtlsdr";
      gain = "-10";
      exposeBeastPort = true;
    };
  };

  # System state version
  system.stateVersion = lib.mkForce "25.11";
}
