# linux-xlnx (Xilinx fork) for Zynq UltraScale+ (aarch64), built from
# xilinx_zynqmp_defconfig. Gives the Xilinx PS/PL drivers, fpga-manager, and
# Xilinx device trees (incl. the KR260 / K26 SOM) that mainline may lack.
# Cross-compiles when referenced from the aarch64 kr260 config built on x86.
#
# Used as: boot.kernelPackages = pkgs.linuxPackagesFor pkgs.linuxZynqmpXlnx;
{ lib, buildLinux, fetchFromGitHub, ... } @ args:

buildLinux (args // {
  version = "6.6.80";
  # xilinx_zynqmp_defconfig sets CONFIG_LOCALVERSION="-xilinx".
  modDirVersion = "6.6.80-xilinx";

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

  # xilinx_zynqmp_defconfig is geared at Xilinx's own rootfs; NixOS needs a few
  # extra options (added here as builds/boots reveal them). The Zynq-7000 kernel
  # additionally had to disable Micrel-PHY/gcc-15-media build breakages that are
  # armv7l/Zynq-7000 specific; ZynqMP is unaffected, so they stay out.
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
  };

  extraMeta = {
    branch = "xlnx-6.6";
    platforms = [ "aarch64-linux" ];
  };
} // (args.argsOverride or { }))
