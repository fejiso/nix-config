{ config, lib, pkgs, modulesPath, ... }:

# Host-specific SD-image bits only; the generic btrfs root (creator, fs, grow,
# compress, extlinux) comes from the shared sd-image-btrfs module via mk-host.
#
# Boot flow: the KR260's on-board QSPI firmware (vendor u-boot, kept as shipped)
# runs distro_bootcmd, which scans the SD card's FAT partition for
# /extlinux/extlinux.conf. Our root is btrfs, which u-boot CANNOT read, so the
# kernel/initrd/dtb + extlinux.conf must live on this FAT partition (mounted at
# /boot at runtime). No BOOT.BIN is written here — the QSPI provides the FSBL /
# PMUFW / ATF / u-boot chain. Set SW1 boot mode to QSPI. (If SD boot mode is set
# instead, the CSU ROM looks for BOOT.BIN on the SD, which we don't ship.)
{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  image.fileName = "nixos-kr260-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

  sdImage = {
    firmwareSize = 256;   # extlinux + kernel/initrd/dtb on the FAT

    # u-boot (from QSPI) can't read the btrfs root, so put kernel/initrd/dtb +
    # extlinux.conf on the FAT partition. Use populateCmd (the build-time
    # populate-into-dir tool), NOT installBootLoader (install-extlinux-conf.sh)
    # — the latter is the runtime activation script and silently ignores `-d`,
    # leaving the FAT bootless (see the z-turn sd-image lesson).
    populateFirmwareCommands = lib.mkForce ''
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} \
        -c ${config.system.build.toplevel} -d ./firmware
    '';

    # Just create the /boot mountpoint on the root fs.
    populateRootCommands = lib.mkForce ''
      mkdir -p ./files/boot
    '';
  };

  # ttyPS0 must be the LAST console= so it becomes /dev/console — otherwise
  # emergency/rescue/sulogin shells and kernel panics go to tty1 (the dead
  # HDMI) and never appear on serial. printk still echoes to both. (ZynqMP uses
  # the same Cadence xuartps driver as Zynq-7000, hence the same ttyPS0.)
  boot.kernelParams = [ "console=tty1" "console=ttyPS0,115200" ];
}
