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

  image.baseName = "nixos-kr260-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";

  sdImage = {
    firmwareSize = 256;   # extlinux + kernel/initrd/dtb on the FAT

    # The stock ZynqMP QSPI u-boot's distro_bootcmd scans the BOOTABLE (active)
    # MBR partition for extlinux.conf. nixpkgs' sd-image marks the btrfs ROOT
    # (p2) active — which u-boot can't read — so it never looks at the FAT (p1)
    # that holds /extlinux/extlinux.conf, and falls through to netboot (this is
    # exactly what the serial log shows). z-turn sidesteps it by shipping a
    # custom u-boot with an explicit bootcmd; kr260 runs the factory QSPI
    # firmware, so flip the active flag to the FAT instead: set p1 bootable,
    # clear p2. MBR partition-entry boot flags are at offsets 446 (p1) / 462 (p2).
    postBuildCommands = ''
      printf '\x80' | dd of="$img" bs=1 seek=446 count=1 conv=notrunc status=none
      printf '\x00' | dd of="$img" bs=1 seek=462 count=1 conv=notrunc status=none
    '';

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

  # Kernel console. "starting NixOS" (u-boot's last message) followed by silence
  # means the kernel's output isn't reaching the serial line. The KR260's
  # micro-USB console can be wired to either Cadence UART — ttyPS0 (ff000000) or
  # ttyPS1 (ff010000) — so register BOTH as consoles: printk goes to all of them,
  # guaranteeing boot output on whichever UART you're watching. `earlycon` adds a
  # polling console from the DT stdout-path u-boot fixups, for the earliest
  # possible messages (localises any early hang). `ignore_loglevel` shows
  # everything. ttyPS0 is listed last so it remains /dev/console.
  boot.kernelParams = [
    "console=tty1"
    "console=ttyPS1,115200"
    "earlycon"
    "ignore_loglevel"
    "console=ttyPS0,115200"
  ];
}
