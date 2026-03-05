{ config, lib, pkgs, ... }:

{
  options.embedded = {
    enable = lib.mkEnableOption "embedded/ARM optimizations for resource-constrained devices";

    serialConsole = lib.mkOption {
      type = lib.types.str;
      default = "ttyS0";
      description = "Serial console device (e.g., ttyS0 for Pine64, ttyAMA0 for RPi)";
    };
  };

  config = lib.mkIf config.embedded.enable {
    # Lighter system packages - remove heavy tools
    # Use mkForce to override common packages that include x86-only software (wine)
    environment.systemPackages = lib.mkForce (with pkgs; [
      vim wget curl git htop btop tree unzip ripgrep fd fzf
      tmux screen
      file pciutils usbutils
      # Explicitly exclude: wine (x86-only), mpv with heavy codecs, large development tools
    ]);

    # Optimize memory usage with zram
    # Override common config which uses lzo
    zramSwap = {
      enable = true;
      algorithm = lib.mkForce "zstd";
      memoryPercent = lib.mkForce 50;  # Higher percentage for limited RAM devices
    };

    # Serial console configuration
    boot.kernelParams = [
      "console=${config.embedded.serialConsole},115200n8"
      "console=tty1"  # Also enable virtual console
    ];

    # Disable unnecessary hardware support by default
    hardware.graphics.enable = lib.mkDefault false;
    hardware.graphics.enable32Bit = lib.mkForce false;  # Not supported on ARM
    hardware.bluetooth.enable = lib.mkDefault true;

    # Disable ZFS (not needed on embedded, may be broken on latest kernels)
    boot.supportedFilesystems = lib.mkForce [ "btrfs" "ext4" "vfat" "f2fs" "xfs" "ntfs" "cifs" "nfs" ];

    # Reduce systemd overhead
    systemd.services.systemd-udev-settle.enable = false;

    # Optimize journald for limited storage
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=30M
    '';

    # Enable fstrim for SD card longevity (if supported)
    services.fstrim.enable = lib.mkDefault true;

    # Clean /tmp on boot to save space
    boot.tmp.cleanOnBoot = true;

    # Override GC to keep 30d on embedded (more conservative)
    systemd.services.nix-garbage-collect.script = lib.mkForce ''
      echo "=== Nix GC start (embedded) ==="
      echo "Store size before: $(du -sh /nix/store | cut -f1)"
      nix-collect-garbage --delete-older-than 30d
      echo "Store size after: $(du -sh /nix/store | cut -f1)"
      echo "=== Nix GC done ==="
    '';

    # Optimize Nix builds on embedded devices
    nix.settings = {
      max-jobs = lib.mkDefault 2;  # Limit parallel builds
      cores = lib.mkDefault 2;     # Limit cores per build
    };
  };
}
