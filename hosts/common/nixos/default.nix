# Common NixOS configuration shared across all NixOS systems
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
    ./nix.nix
    ./users.nix
    ./security.nix
    ./networking.nix
    ./services.nix
    ./sops.nix
    ./distributed-build.nix
    ./home-manager.nix
    ./netbird.nix
    inputs.home-manager.nixosModules.home-manager
    ../../../modules/nixos/nfs-mounts.nix
  ];

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.modifications
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      permittedInsecurePackages = lib.mkDefault [
        "mbedtls-2.28.10"
        "freeimage-3.18.0-unstable-2024-04-18"
        "qtwebengine-5.15.19"
      ];
    };
  };

  # Enable NFS mounts
  services.nfs-mounts.enable = true;

  # Set hostname
  networking.hostName = hostname;

  # Bootloader configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  system.autoUpgrade.enable = true;

  # Locale and timezone
  # time.timeZone is managed by automatic-timezoned service
  i18n.defaultLocale = "en_IE.UTF-8";
  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_IE.UTF-8";
    LC_IDENTIFICATION = "en_IE.UTF-8";
    LC_MEASUREMENT = "en_IE.UTF-8";
    LC_MONETARY = "en_IE.UTF-8";
    LC_NAME = "en_IE.UTF-8";
    LC_NUMERIC = "en_IE.UTF-8";
    LC_PAPER = "en_IE.UTF-8";
    LC_TELEPHONE = "en_IE.UTF-8";
    LC_TIME = "en_IE.UTF-8";
  };

  # Console configuration
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "alt-intl";
  };

  # System packages available to all users
  environment.systemPackages = with pkgs; [
    vim
    wget
    curl
    git
    git-crypt
    htop
    btop
    tree
    unzip
    zip
    ripgrep
    fd
    fzf
    firefox
    gnupg
    nix-index
    fish
    gcc
    zellij
    zoxide
    python3
    mpv
    file
    pinentry-curses
    wine
    wl-clipboard
    lsof
    nmap
    bind.dnsutils
    ddrescue
    smartmontools
    vscode
    sqlite
    inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
  ];

  # Enable documentation
  documentation.nixos.enable = true;

  # Hardware
  hardware.enableRedistributableFirmware = true;
  hardware.graphics.enable = true;
  hardware.enableAllFirmware = true;
  hardware.graphics.enable32Bit = true;
  hardware.graphics.extraPackages = with pkgs; [
    intel-media-driver
    libva
  ];
  hardware.bluetooth.enable = true;
  services.blueman.enable = true;

  # Memory management
  zramSwap = {
    enable = true;
    algorithm = "lzo";
    memoryPercent = 10;
  };

  # Services
  services.dbus.enable = true;
  services.openssh.enable = true;

  # Fonts
  fonts.packages = with pkgs; [
    noto-fonts
    noto-fonts-cjk-sans
    noto-fonts-color-emoji
    nerd-fonts.fira-code
    fira-code
  ];

  # Users
  programs.fish.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
