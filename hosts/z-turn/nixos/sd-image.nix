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
    # chainloads u-boot.img; u-boot's distro_bootcmd then scans the FAT for
    # /extlinux/extlinux.conf. Our root is btrfs, which u-boot CANNOT read, so
    # the kernel/initrd/dtb + extlinux.conf must live on this FAT partition
    # (which is also mounted at /boot at runtime). NOTE: use populateCmd
    # (extlinux-conf-builder, the build-time populate-into-dir tool), NOT
    # installBootLoader (install-extlinux-conf.sh) — the latter is the runtime
    # activation script and silently ignores `-d`, leaving the FAT bootless.
    populateFirmwareCommands = lib.mkForce ''
      cp ${uboot}/boot.bin firmware/BOOT.BIN
      cp ${uboot}/u-boot.img firmware/u-boot.img
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./firmware
    '';

    # Default armv7l sd-image installs extlinux to the (btrfs) root /boot, which
    # u-boot can't read — we put it on the FAT above instead. Here just create
    # the /boot mountpoint on the root fs.
    populateRootCommands = lib.mkForce ''
      mkdir -p ./files/boot
    '';
  };

  # ttyPS0 must be the LAST console= so it becomes /dev/console — otherwise
  # emergency/rescue/sulogin shells and kernel panics go to tty1 (the dead
  # HDMI) and never appear on serial. printk still echoes to both.
  boot.kernelParams = [ "console=tty1" "console=ttyPS0,115200" ];
}
