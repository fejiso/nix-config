# u-boot-xlnx (Xilinx fork) for the MYIR Z-turn (Zynq-7020).
# The modern Xilinx u-boot uses one unified defconfig for all Zynq-7000 boards
# and selects the board at build time via DEVICE_TREE. Its SPL (spl/boot.bin)
# acts as the FSBL, so no Vivado-generated FSBL is needed.
#
# Cross-compiles automatically: when referenced from the z-turn config (whose
# pkgs is armv7l-host/x86-build), buildUBoot picks up the arm cross toolchain.
{ lib, buildUBoot, fetchFromGitHub }:

buildUBoot {
  version = "xlnx-2024.2";
  src = fetchFromGitHub {
    owner = "Xilinx";
    repo = "u-boot-xlnx";
    # xlnx_rebase_v2024.01_2024.2
    rev = "7f6ec94aac7eacfec07bd45c83a6d17df4b7d383";
    hash = "sha256-qeyvbpDvgg3Uu9Rr7yQIzIMhbLxGIuSAc/T95GPMDL8=";
  };

  defconfig = "xilinx_zynq_virt_defconfig";
  # Board select. This is the V5 board revision (ethernet PHY at MDIO addr 3);
  # the non-v5 DT (phy@0) gives "Could not get PHY for eth0: addr 0" in u-boot.
  extraMakeFlags = [ "DEVICE_TREE=zynq-zturn-v5" ];

  # Boot NixOS extlinux directly from the FAT (mmc 0:1). The stock distro_bootcmd
  # only scans *bootable* partitions for extlinux.conf, but the NixOS sd-image
  # sets the active flag on the btrfs ROOT partition (which u-boot can't read) —
  # so it never looks at the FAT where extlinux.conf + kernel/initrd/dtb live.
  # Override bootcmd to sysboot the FAT explicitly; keep distro_bootcmd as a
  # fallback (e.g. for future netboot).
  extraConfig = ''
    CONFIG_USE_BOOTCOMMAND=y
    CONFIG_BOOTCOMMAND="if mmc dev 0; then sysboot mmc 0:1 any 0x03000000 /extlinux/extlinux.conf; fi; run distro_bootcmd"
  '';

  extraMeta.platforms = [ "armv7l-linux" ];
  filesToInstall = [ "spl/boot.bin" "u-boot.img" ];
}
