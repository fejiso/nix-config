{ config, lib, pkgs, modulesPath, ... }:

let
  uboot = pkgs.ubootZturn;   # u-boot-xlnx (SPL = FSBL), from the additions overlay
in
{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-armv7l-multiplatform.nix")
  ];

  # Image build only needs the ext4 root; drop the /boot/firmware mount.
  fileSystems = lib.mkForce {
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
  };

  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  image.fileName = "nixos-z-turn-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

  sdImage = {
    compressImage = true;
    expandOnBoot = true;
    firmwareSize = 256;   # holds BOOT.BIN + u-boot.img + extlinux + kernel/initrd

    # The Zynq bootrom loads BOOT.BIN (u-boot SPL) from the FAT partition, which
    # chainloads u-boot.img; u-boot then boots via extlinux (installed here too).
    populateFirmwareCommands = lib.mkForce ''
      cp ${uboot}/boot.bin firmware/BOOT.BIN
      cp ${uboot}/u-boot.img firmware/u-boot.img
      ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
    '';
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  boot.kernelParams = [ "console=ttyPS0,115200" "console=tty1" ];
}
