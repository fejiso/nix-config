{ config, lib, pkgs, modulesPath, ... }:

# Host-specific SD-image bits only; the generic btrfs root (creator, fs, grow,
# compress, extlinux) comes from the shared sd-image-btrfs module via mk-host.
let
  uboot = pkgs.ubootZturn;   # u-boot-xlnx (SPL = FSBL), from the additions overlay
in
{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-armv7l-multiplatform.nix")
  ];

  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  image.fileName = "nixos-z-turn-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

  sdImage = {
    firmwareSize = 256;   # holds BOOT.BIN + u-boot.img + extlinux + kernel/initrd

    # The Zynq bootrom loads BOOT.BIN (u-boot SPL) from the FAT partition, which
    # chainloads u-boot.img; u-boot then boots via extlinux (installed here too).
    populateFirmwareCommands = lib.mkForce ''
      cp ${uboot}/boot.bin firmware/BOOT.BIN
      cp ${uboot}/u-boot.img firmware/u-boot.img
      ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
    '';
  };

  boot.kernelParams = [ "console=ttyPS0,115200" "console=tty1" ];
}
