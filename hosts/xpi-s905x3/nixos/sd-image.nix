{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Override fileSystems for SD image to use ext4 (not btrfs)
  # SD image module only supports ext4 natively
  # After first boot, btrfs-convert-firstboot will convert to btrfs
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
  image.fileName = "nixos-xpi-s905x3-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

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

    # Populate root with bootloader configuration
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };

  # Boot configuration for SD image
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Kernel parameters for first boot
  boot.kernelParams = [
    "console=ttyAML0,115200"
    "console=tty1"
  ];
}
