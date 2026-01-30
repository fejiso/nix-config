# Hispanas specific NixOS configuration
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
    ../../../modules/nixos/adsb-readsb.nix
    ../../../modules/nixos/adsb-feeders.nix
    # Add appropriate nixos-hardware module for your specific Lenovo model
    # inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-carbon-gen11
  ];

  # ADS-B configuration
  # Standalone readsb disabled, using Ultrafeeder
  services.adsb-readsb = {
    enable = false;
    enableRtlSdrHardware = true;
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

  services.adsb-feeders = {
    adsbfi = {
      enable = true;
      uuidSecretFile = config.sops.secrets.adsb-uuid.path;
      latitude = "$(cat ${config.sops.secrets.adsb-lat.path})";
      longitude = "$(cat ${config.sops.secrets.adsb-lon.path})";
      altitude = "$(cat ${config.sops.secrets.adsb-alt.path})";
      mlat = true;
      webPort = 8081; # 8080 used by webcam
      
      # Handle SDR decoding directly
      deviceType = "rtlsdr";
      gain = "-10";
      exposeBeastPort = true;
    };
  };

  # Host-specific networking
  networking.hostName = "hispanas";


  # Create mjpg-streamer user
  users.users.mjpg-streamer = {
    isSystemUser = true;
    group = "video";
  };
  users.groups.video = {};

  # Emilia user account
  users.users.emilia = {
    isNormalUser = true;
    description = "Emilia";
    extraGroups = [ "video" "audio" "networkmanager" ];
    packages = with pkgs; [
      telegram-desktop
    ];
  };

  # Support Spanish locale
  i18n.supportedLocales = [ "es_ES.UTF-8/UTF-8" "en_IE.UTF-8/UTF-8" ];

  # Set Spanish locale for emilia only
  systemd.tmpfiles.rules = [
    "d /home/emilia/.config/environment.d 0755 emilia users -"
  ];
  environment.etc."skel/.config/environment.d/locale.conf".text = "";
  system.activationScripts.emiliaLocale = ''
    mkdir -p /home/emilia/.config/environment.d
    echo 'LANG=es_ES.UTF-8' > /home/emilia/.config/environment.d/locale.conf
    chown -R emilia:users /home/emilia/.config/environment.d
  '';

  # Cinnamon desktop (Linux Mint style)
  services.xserver = {
    enable = true;
    displayManager.lightdm.enable = true;
    desktopManager.cinnamon.enable = true;
  };

  # Disable GNOME's ssh-agent (conflicts with programs.ssh.startAgent)
  services.gnome.gnome-keyring.enable = lib.mkForce false;
  services.gnome.gcr-ssh-agent.enable = false;

  # Autologin for emilia
  services.displayManager.autoLogin = {
    enable = true;
    user = "emilia";
  };

  # Autostart telegram-desktop
  environment.etc."xdg/autostart/telegram.desktop".text = ''
    [Desktop Entry]
    Type=Application
    Name=Telegram
    Exec=${pkgs.telegram-desktop}/bin/Telegram
    Hidden=false
    NoDisplay=false
    X-GNOME-Autostart-enabled=true
    X-Cinnamon-Autostart-enabled=true
  '';

  # Open firewall for webcam stream and adsbfi map
  networking.firewall.allowedTCPPorts = [ 8080 8081 ];

  # System state version
  system.stateVersion = "25.05";
}
