# linux-xlnx (Xilinx fork) for Zynq UltraScale+ (aarch64), built from
# xilinx_zynqmp_defconfig. Gives the Xilinx PS/PL drivers, fpga-manager, and
# Xilinx device trees (incl. the KR260 / K26 SOM) that mainline may lack.
# Cross-compiles when referenced from the aarch64 kr260 config built on x86.
#
# Used as: boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linuxZynqmpXlnx;
{ lib, buildLinux, fetchFromGitHub, ... } @ args:

buildLinux (args // {
  version = "6.6.80";
  # xilinx_zynqmp_defconfig leaves CONFIG_LOCALVERSION empty (unlike the
  # Zynq-7000 defconfig, which sets "-xilinx"), so kernelrelease == 6.6.80.
  modDirVersion = "6.6.80";

  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "linux-xlnx";
    # xlnx_rebase_v6.6_LTS (Linux 6.6.80 base) — same rev/hash as the Zynq-7000
    # kernel.nix: linux-xlnx is one tree for all Xilinx families, so this FOD is
    # shared/deduped. ZynqMP just needs a different defconfig + platform below.
    rev = "f5fffda2f301003724f1f54691fd44983137a56c";
    hash = "sha256-Lt+dxK3Z0HKOFe9xuDUPEkulr5q8ViM/eT2YJakEjG0=";
  };

  defconfig = "xilinx_zynqmp_defconfig";

  # The xilinx_zynqmp_defconfig is an embedded/PS-only config: it leaves ACPI,
  # the security LSM stack (apparmor/landlock/lockdown/yama), RPi/BCM2835,
  # Tegra/Allwinner, Xen, PCIEAER, SCHED_CORE, etc. disabled. nixpkgs' common
  # kernel-config (merged into every buildLinux) requests those symbols, and
  # since their Kconfig dependencies aren't met here `make olddefconfig` drops
  # them — generate-config.pl then errors with "unused option: ...". Downgrade
  # those to warnings (same as nixpkgs' own embedded/vendor kernels, e.g. RPi).
  ignoreConfigErrors = true;

  # xilinx_zynqmp_defconfig is geared at Xilinx's own rootfs; NixOS needs a few
  # extra options (added here as builds/boots reveal them). The Zynq-7000 kernel
  # also builds in its board's Micrel PHY; the KR260's PHY differs, so that
  # stays out. The linux-xlnx vendor modpost-breakers below are NOT arch-specific
  # (they bite ZynqMP just as they do Zynq-7000) — see pkgs/zynq/kernel.nix.
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

    # Build ext4 and btrfs in so the SD root mounts at boot without an initrd
    # module (the root is btrfs).
    EXT4_FS = yes;
    EXT4_USE_FOR_EXT2 = yes;
    BTRFS_FS = yes;

    # linux-xlnx vendor modules that fail `make modules` modpost (broken
    # namespace imports / undefined symbols) and aren't on this board: a TI
    # PMBUS regulator, the Xilinx staging MPEG2-TS muxer, and the Versal (not
    # ZynqMP) sysmon. Identical to the Zynq-7000 workarounds.
    SENSORS_TPS544 = no;
    XLNX_TSMUX = no;
    VERSAL_SYSMON = no;
    VERSAL_SYSMON_CORE = no;
    VERSAL_SYSMON_I2C = no;
  };

  extraMeta = {
    branch = "xlnx-6.6";
    platforms = [ "aarch64-linux" ];
  };
} // (args.argsOverride or { }))
