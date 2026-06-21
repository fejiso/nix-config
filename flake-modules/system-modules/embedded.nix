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
      # Slim system package set. mkForce replaces the WHOLE list, which would
      # also wipe NixOS' requiredPackages (coreutils/findutils/procps/util-linux),
      # `nix`, and the auto-added user login shells (`systemShells` — the passwd
      # shell is the profile path, so dropping it breaks login). Re-include them.
      environment.systemPackages =
        lib.mkForce (
          (lib.filter lib.types.shellPackage.check
            (lib.unique (lib.mapAttrsToList (_: u: u.shell) config.users.users)))
          ++ [ config.nix.package ]
          ++ (with pkgs; [
            coreutils-full findutils diffutils gnugrep gnused gawk
            gnutar gzip bzip2 xz zstd
            util-linux procps less which iproute2
            vim wget curl git htop btop tree unzip ripgrep fd fzf
            tmux screen file pciutils usbutils
          ])
        );

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

      # Journald volatile (SD longevity)
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
    })
  ];
}
;

  # Trimmed-UI variant slot. Identical to `embedded` for now (no UI yet); exists
  # so a future board can import a constrained desktop without re-plumbing.
  flake.modules.nixos.embedded-ui = config.flake.modules.nixos.embedded;
}
