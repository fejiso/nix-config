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
    ../../common/nixos/nix.nix
    ../../common/nixos/users.nix
    ../../common/nixos/security.nix
    ../../common/nixos/networking.nix
    ../../common/nixos/services.nix
    ../../common/nixos/sops.nix
    ../../common/nixos/distributed-build.nix
    ../../common/nixos/netbird.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/7f1bd4db-58b3-40aa-be5c-d38ba434cfcb";
    allowDiscards = true;
  };
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.resumeDevice = "/dev/disk/by-uuid/E02A-0157";
  boot.kernelParams = [ "resume_offset=533760" ];

  # Networking
  networking.hostName = "blacktop";
  networking.networkmanager.enable = true;

  # Window managers
  programs.niri.enable = true;

  # Services
  services.pcscd.enable = true;  # Smart card daemon for hardware tokens
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.udev.extraRules = ''
    # TOKEN2 FIDO2 Security Key - give plugdev group access
    SUBSYSTEM=="usb", ATTR{idVendor}=="349e", ATTR{idProduct}=="0026", GROUP="plugdev", MODE="0664"
  '';
  services.logind.lidSwitchExternalPower = "ignore";
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.displayManager.gdm.autoSuspend = false;
  services.xserver.displayManager.defaultSession = "niri";
  services.xserver.desktopManager.gnome.enable = true;
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
  services.btrfs.autoScrub.enable = true;

  # Localization
  time.timeZone = "Europe/Dublin";
  i18n.defaultLocale = "en_IE.UTF-8";

  # User configuration
  users.groups.plugdev = {};
  users.users.z-247 = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" "plugdev" ];
    packages = with pkgs; [
      amazon-q-cli
      tree
    ];
  };

  # System packages
  environment.systemPackages = with pkgs; [
    vim
    wget
    firefox
    git
    alacritty
    fuzzel
    swaylock
    mako
    swayidle
    usbutils
    pcsclite
    pcsc-tools
  ];

  # System state version
  system.stateVersion = "25.05";
}
