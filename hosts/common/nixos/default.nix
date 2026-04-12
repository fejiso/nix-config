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
    ./seedlink.nix
    ./socks-proxy.nix
    ./podman.nix
    inputs.home-manager.nixosModules.home-manager
    ../../../modules/nixos/nfs-mounts.nix
    ../../../modules/nixos/backup.nix
  ];

  # Enable backups on all nodes
  services.backup.enable = true;

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

  # Symlink root's nix config to z-247's so sudo inherits access-tokens etc.
  systemd.tmpfiles.rules = [
    "d /root/.config/nix 0755 root root -"
    "L+ /root/.config/nix/nix.conf - - - - /home/z-247/.config/nix/nix.conf"
  ];

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

  # kmscon - modern TTY with TrueType/emoji support
  services.kmscon = {
    enable = true;
    hwRender = true;
    fonts = [
      { name = "FiraCode Nerd Font Mono"; package = pkgs.nerd-fonts.fira-code; }
      { name = "Noto Color Emoji"; package = pkgs.noto-fonts-color-emoji; }
    ];
    extraConfig = "font-size=14";
  };
  services.xserver.xkb = {
    layout = "us";
    variant = "alt-intl";
  };

  # nix-ld for running unpatched binaries (uv/pip venvs, etc.)
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    stdenv.cc.cc.lib
    zlib
  ];

  # System packages available to all users
  environment.systemPackages = with pkgs; [
    vim
    wget
    aria2
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
    wl-clipboard
    lsof
    nmap
    bind.dnsutils
    ddrescue
    smartmontools
    sqlite
    python3Packages.rns
    python3Packages.nomadnet
    yggdrasil
    i2pd
    pipx
    parallel-full
    age
    sops
    ssh-to-age
    rclone
    python3Packages.meshtastic
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

  # Enable Magic SysRq (REISUB)
  boot.kernel.sysctl."kernel.sysrq" = 1;

  # Memory management: zswap for hosts with swap, zram for those without
  boot.kernelParams = lib.mkIf (config.swapDevices != []) [
    "zswap.enabled=1"
    "zswap.compressor=lz4"
    "zswap.zpool=z3fold"
  ];
  zramSwap = {
    enable = config.swapDevices == [];
    algorithm = "lz4";
    memoryPercent = 10;
  };

  # OOM management
  systemd.oomd.enable = true;
  systemd.slices."user".sliceConfig = {
    ManagedOOMMemoryPressure = "kill";
    MemoryMax = "80%";
  };

  # Journald optimization for SSD longevity
  # Embedded systems override this with volatile storage
  services.journald.extraConfig = lib.mkDefault ''
    Compress=yes
    SystemMaxUse=500M
    SystemMaxFileSize=50M
    MaxRetentionSec=1month
  '';

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

  # dconf - needed for home-manager gtk/dconf settings to apply during activation
  programs.dconf.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
