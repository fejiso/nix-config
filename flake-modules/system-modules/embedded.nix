{ config, ... }: {
  # `embedded` is now ADDITIVE: it layers resource constraints on top of the
  # universal `cli` base. The heavy fleet services (mesh, audio, etc.) are no
  # longer in `cli` — they live in opt-in `mesh`/`desktop-services` aspects that
  # embedded hosts simply don't import — so there's nothing to mkForce-subtract.
  flake.modules.nixos.embedded =
{ config, lib, pkgs, ... }:

{
  options.embedded = {
    enable = lib.mkEnableOption "embedded/ARM optimizations for resource-constrained devices";

    serialConsole = lib.mkOption {
      type = lib.types.str;
      default = "ttyS0";
      description = "Serial console device (e.g., ttyS0 for Pine64, ttyAMA0 for RPi)";
    };

    crossSafe = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        For cross-compiled boards (e.g. armv7l z-turn). Forces bash as the login
        shell and disables components of `cli` that don't cross-compile or run a
        target binary at build time: fish, nix-ld, kmscon, fontconfig's fc-cache,
        nix-serve (Perl), and redistributable firmware. Leave false for natively
        built boards (rpi3/pine64/xpi-s905x3) so they keep fish etc.
      '';
    };
  };

  config = lib.mkMerge [
    (lib.mkIf config.embedded.enable {
      # ADDITIVE, not a replacement. Embedded inherits the ENTIRE `cli` base
      # package set — including the systemd CLI (networkctl/systemctl/journalctl),
      # plus NixOS' always-on requiredPackages (coreutils/findutils/util-linux/
      # procps) and the login shells. We only ADD the hardware/diagnostic extras
      # the base lacks. (An earlier `mkForce [...]` whitelist kept silently
      # dropping essentials — systemd, shells — so it's gone. Heavy UI/media like
      # mpv and wl-clipboard aren't in the base; they live in `desktop`, which
      # embedded doesn't import, so there's nothing to subtract here.)
      environment.systemPackages = with pkgs; [
        ethtool iputils tmux screen pciutils usbutils
      ];

      # zram (zstd, 50% for limited RAM)
      zramSwap = {
        enable = true;
        algorithm = lib.mkForce "zstd";
        memoryPercent = lib.mkForce 50;
      };

      # Serial console
      boot.kernelParams = [
        "console=${config.embedded.serialConsole},115200n8"
        "console=tty1"
      ];

      # Trim hardware support
      hardware.graphics.enable = lib.mkDefault false;
      hardware.graphics.enable32Bit = lib.mkForce false;
      hardware.bluetooth.enable = lib.mkDefault true;
      boot.supportedFilesystems = lib.mkForce [ "btrfs" "ext4" "vfat" "f2fs" "xfs" "ntfs" "cifs" "nfs" ];
      systemd.services.systemd-udev-settle.enable = false;

      # Drop the rendered NixOS manual (HTML option reference + nixos-help):
      # large and headless-useless.
      documentation.nixos.enable = lib.mkForce false;

      # Disable the man-db whatis/apropos CACHE (both the build-time index and
      # the runtime `mandb` service). The cache is a `buildEnv` over every
      # systemPackage's man output, and on armv7l forcing it pulls a broken
      # transitive package (`efivar`) that aborts the whole evaluation. The man
      # pages themselves still install via `documentation.man.enable`, so `man ip`
      # etc. work — only `apropos`/`whatis` keyword search loses its index.
      documentation.man.cache.enable = lib.mkForce false;
      documentation.man.cache.generateAtRuntime = lib.mkForce false;

      # Keep volatile state in RAM, off the SD card: /tmp on tmpfs (capped at
      # 25% of RAM) and journald fully volatile (capped at 30M of runtime RAM).
      boot.tmp.useTmpfs = true;
      boot.tmp.tmpfsSize = "25%";
      services.journald.extraConfig = ''
        Storage=volatile
        RuntimeMaxUse=30M
      '';
      services.fstrim.enable = lib.mkDefault true;
      boot.tmp.cleanOnBoot = true;

      # NetworkManager (~25 MiB) -> systemd-networkd, DHCP on the wired NIC.
      # WiFi embedded hosts must re-enable NetworkManager or configure wireless.
      networking.networkmanager.enable = lib.mkForce false;
      networking.useNetworkd = lib.mkDefault true;
      services.resolved.enable = lib.mkDefault true;
      systemd.network.networks."10-embedded-wired" = {
        matchConfig.Name = "en* eth*";
        networkConfig.DHCP = "yes";
        linkConfig.RequiredForOnline = "routable";
      };

      # Conservative GC + limited build parallelism
      systemd.services.nix-garbage-collect.script = lib.mkForce ''
        echo "=== Nix GC start (embedded) ==="
        echo "Store size before: $(du -sh /nix/store | cut -f1)"
        nix-collect-garbage --delete-older-than 30d
        echo "Store size after: $(du -sh /nix/store | cut -f1)"
        echo "=== Nix GC done ==="
      '';
      nix.settings = {
        max-jobs = lib.mkDefault 2;
        cores = lib.mkDefault 2;
      };
    })

    # Cross-compile safety: disable `cli` components that fail to cross-compile
    # or run a target binary at build time. (fish cross-compiles via the
    # overlays/ man-page-skip override, so it stays — no bash fallback needed.)
    (lib.mkIf (config.embedded.enable && config.embedded.crossSafe) {
      programs.nix-ld.enable = lib.mkForce false;
      services.kmscon.enable = lib.mkForce false;
      fonts.fontconfig.enable = lib.mkForce false;
      services.nix-serve.enable = lib.mkForce false;
      hardware.enableRedistributableFirmware = lib.mkForce false;
      hardware.firmware = lib.mkForce [ ];

      # efivar is marked broken on armv7l, but it's only pulled in transitively
      # by man/dbus aggregation buildEnvs (no real UEFI need on a Zynq board).
      # Allow it to evaluate (per nixpkgs' problems.handlers API) instead of
      # refusing — this is the single fix for the cascade of efivar eval errors.
      nixpkgs.config.problems.handlers.efivar.broken = "warn";
    })
  ];
}
;

  # Trimmed-UI variant slot. Identical to `embedded` for now (no UI yet); exists
  # so a future board can import a constrained desktop without re-plumbing.
  flake.modules.nixos.embedded-ui = config.flake.modules.nixos.embedded;
}
