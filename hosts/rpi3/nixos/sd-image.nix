{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Override fileSystems for SD image to use ext4 (not btrfs)
  # SD image module only supports ext4 natively
  # After first boot, you can convert to btrfs manually
  fileSystems = lib.mkForce {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
  };

  # Disable btrfs autoscrub for SD image (ext4)
  services.btrfs.autoScrub.enable = lib.mkForce false;

  # Disable x86-specific graphics for ARM
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # Image configuration
  image.fileName = "nixos-rpi3-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

  # SD image configuration
  sdImage = {
    # Compress the image to save space
    compressImage = true;

    # Expand root partition on first boot
    expandOnBoot = true;

    # Firmware partition size (in MB)
    firmwareSize = 512;

    # Populate firmware with bootloader files
    populateFirmwareCommands = ''
      ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
    '';

    # UUID for root partition
    rootPartitionUUID = lib.mkForce "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
  };

  # Boot configuration for SD image
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Kernel parameters for first boot
  boot.kernelParams = [
    "console=ttyAMA0,115200"
    "console=tty1"
  ];
}
