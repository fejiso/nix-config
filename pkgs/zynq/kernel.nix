# linux-xlnx (Xilinx fork) for Zynq-7000 (armv7l), built from xilinx_zynq_defconfig.
# Gives the Xilinx PS drivers, fpga-manager, and xilinx device trees that mainline
# lacks. Cross-compiles when referenced from the armv7l z-turn config.
#
# Used as: boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linuxZynqXlnx;
{ lib, buildLinux, fetchFromGitHub, ... } @ args:

buildLinux (args // {
  version = "6.6.80";
  # xilinx_zynq_defconfig sets CONFIG_LOCALVERSION="-xilinx".
  modDirVersion = "6.6.80-xilinx";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "linux-xlnx";
    # xlnx_rebase_v6.6_LTS (Linux 6.6.80 base)
    rev = "f5fffda2f301003724f1f54691fd44983137a56c";
    hash = "sha256-Lt+dxK3Z0HKOFe9xuDUPEkulr5q8ViM/eT2YJakEjG0=";
  };

  defconfig = "xilinx_zynq_defconfig";

  # xilinx_zynq_defconfig is geared at Xilinx's own rootfs; NixOS needs a few
  # extra options (added here as builds/boots reveal them).
  structuredExtraConfig = with lib.kernel; {
    # systemd / NixOS stage-2 essentials commonly missing from vendor defconfigs:
    AUTOFS_FS = yes;
    CGROUPS = yes;
    DEVTMPFS = yes;
    DEVTMPFS_MOUNT = yes;
    OVERLAY_FS = yes;
    # initrd (NixOS stage-1) needs these:
    TMPFS = yes;
    TMPFS_POSIX_ACL = yes;
    TMPFS_XATTR = yes;

    # The xlnx defconfig only has the dead EXT3 symbol; the SD root is ext4, so
    # build the ext4 driver in (it also handles ext2/3) for boot-time mount.
    EXT4_FS = yes;
    EXT4_USE_FOR_EXT2 = yes;

    # The Xilinx multimedia stack (DRM display + V4L2 media + HDMI/HDCP) doesn't
    # compile under gcc-15 (e.g. xilinx-hdcp2x-rx.c: implicit FIELD_PREP) and is
    # not needed on a headless board. Disable it.
    VIDEO_XILINX = no;
    DRM_XLNX = no;

    # Vendor modules that fail modpost (broken namespace imports / undefined
    # symbols) and are irrelevant to a Zynq-7020: a TI PMBUS regulator not on
    # this board, the staging MPEG2-TS muxer, and the Versal (not Zynq) sysmon.
    SENSORS_TPS544 = no;
    XLNX_TSMUX = no;
    VERSAL_SYSMON = no;
    VERSAL_SYSMON_CORE = no;
    VERSAL_SYSMON_I2C = no;
  };

  extraMeta = {
    branch = "xlnx-6.6";
    platforms = [ "armv7l-linux" ];
  };
} // (args.argsOverride or { }))
