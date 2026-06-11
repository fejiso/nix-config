{ ... }: {
  flake.modules.nixos.default = { inputs, outputs, lib, config, pkgs, hostname, ... }: {
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
          "electron-39.8.10"
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

    # Enable Hetzner Storage Box mount
    services.storagebox-mount.enable = true;

    # Set hostname
    networking.hostName = hostname;

    # Bootloader configuration
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
    system.autoUpgrade.enable = true;

    # Locale and timezone
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
      # Software rendering: kmscon's GL renderer segfaults against the nvidia
      # driver, crashing every secondary VT. CPU-rendered consoles are fine.
      hwRender = false;
      fonts = [
        { name = "FiraCode Nerd Font Mono"; package = pkgs.nerd-fonts.fira-code; }
        # Monochrome (outline) emoji — kmscon's freetype renderer SEGVs on
        # color/bitmap CBDT glyphs (Noto Color Emoji), so use Noto Emoji.
        { name = "Noto Emoji"; package = pkgs.noto-fonts-monochrome-emoji; }
      ];
      # Use the pango engine, not kmscon's freetype backend: the latter
      # SEGVs in render_glyph against freetype 2.14 (it's deprecated/removed
      # upstream). pango renders via mod-pango.so and avoids the crash.
      extraConfig = ''
        font-size=14
        font-engine=pango
      '';
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

    documentation.nixos.enable = true;

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

    # Journald optimization for SSD longevity (volatile systems override)
    services.journald.extraConfig = lib.mkDefault ''
      Compress=yes
      SystemMaxUse=500M
      SystemMaxFileSize=50M
      MaxRetentionSec=1month
    '';

    services.dbus.enable = true;
    services.openssh.enable = true;

    fonts.packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      nerd-fonts.fira-code
      fira-code
    ];

    programs.fish.enable = true;
    programs.dconf.enable = true;

    # Fallback only — every host should pin its own install-time stateVersion.
    system.stateVersion = lib.mkDefault "25.05";
  };
}
