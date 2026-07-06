{ ... }: {
  flake.modules.nixos.cli = { inputs, outputs, lib, config, pkgs, hostname, ... }: {
    # Enable backups on all nodes
    services.backup.enable = lib.mkDefault true;
    # Public TLS fingerprint of butthead's kopia server (SHA256, hex, no colons).
    # Pinned by every remote client; refresh from `cat <repoPath>/server-fingerprint`
    # on butthead if the server cert is ever regenerated.
    services.backup.serverFingerprint = lib.mkDefault "D50A92ACEBF880EC64252ACCC43E6B26AB57A9ACC84C6E452C7C0265ACB87BD9";

    # Global snapshot exclusions — applied to every host's global kopia policy.
    # Patterns are globs relative to each snapshot source; `**/` matches at any
    # depth. Extend or override per-host via services.backup.ignore (mkDefault
    # here means a per-host assignment replaces, not appends).
    services.backup.ignore = lib.mkDefault [
      "**/.stversions"
      "**/logs"
      "**/target"
      "**/debug"
      "**/*.h5"
      "**/Syncthing"
      "**/.local/share/containers"
      "**/.venv"
      "**/.cache"
      "**/.wine*"
      "**/.mozilla"
      "**/.vscode"
      "**/.platformio"
      "**/poly_frame"
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
    services.nfs-mounts.enable = lib.mkDefault true;

    # Enable Hetzner Storage Box mount
    services.storagebox-mount.enable = lib.mkDefault true;

    # Set hostname
    networking.hostName = hostname;

    # Bootloader configuration
    boot.loader.systemd-boot.enable = lib.mkDefault true;
    boot.loader.efi.canTouchEfiVariables = lib.mkDefault true;
    system.autoUpgrade.enable = lib.mkDefault true;

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
      enable = lib.mkDefault true;
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
      file
      pinentry-curses
      lsof
      nmap
      bind.dnsutils
      ddrescue
      smartmontools
      sqlite
      pipx
      # parallel-full bundles extra perl modules (Text-CSV, Math-Base-Convert for
      # --csv/--sql) whose build runs pod2text/pod2man with the TARGET perl — which
      # can't exec on the x86 build host when cross-compiling (Exec format error).
      # The core `parallel` binary is identical and cross-clean; use it on cross.
      (if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform then parallel-full else parallel)
      age
      sops
      ssh-to-age
      rclone
      # The flake's home-manager is a per-system output with no cross variant, so
      # on a cross-built board (armv7l z-turn) it forces a NATIVE armv7l build for
      # which no builder exists. Use the cross-compilable nixpkgs `home-manager`
      # when build != host; native hosts keep the version-matched flake package.
      (if pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform
       then inputs.home-manager.packages.${pkgs.stdenv.hostPlatform.system}.default
       else pkgs.home-manager)
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
    hardware.bluetooth.enable = lib.mkDefault true;
    services.blueman.enable = lib.mkDefault true;

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
