# Common desktop configuration shared between desktop systems
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  # Window managers
  programs.niri.enable = true;

  # Gaming
  programs.steam = {
    enable = true;
    remotePlay.openFirewall = true; # Open ports in the firewall for Steam Remote Play
    dedicatedServer.openFirewall = true; # Open ports in the firewall for Source Dedicated Server
  };

  # Desktop services
  services.pcscd.enable = true;  # Smart card daemon for hardware tokens
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.udev.extraRules = ''
    # TOKEN2 FIDO2 Security Key - give plugdev group access
    SUBSYSTEM=="usb", ATTR{idVendor}=="349e", ATTR{idProduct}=="0026", GROUP="plugdev", MODE="0664"
  '';

  # Display manager and desktop environment
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.displayManager.gdm.autoSuspend = false;
  services.displayManager.defaultSession = "niri";
  services.desktopManager.gnome.enable = false;
  
  # Disable GNOME GCR SSH agent to avoid conflict
  services.gnome.gcr-ssh-agent.enable = false;

  # User groups and configuration
  users.groups.plugdev = {};
  users.users.z-247 = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "plugdev" "media-services" ];
    packages = with pkgs; [
      amazon-q-cli
      tree
    ];
  };

  # Desktop system packages
  environment.systemPackages = with pkgs; [
    wget
    firefox
    git
    alacritty
    fuzzel
    swaylock
    pciutils
    mako
    swayidle
    usbutils
    pcsclite
    pcsc-tools
  ];

  # SSH configuration for desktop access
  services.openssh = {
    enable = true;
    ports = [ 22 ];
    settings = {
      PasswordAuthentication = lib.mkForce true;
      UseDns = true;
      X11Forwarding = false;
      PermitRootLogin = lib.mkForce "yes";
    };
  };

  # Networking
  networking.networkmanager.enable = true;

  # Localization  
  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";
}
