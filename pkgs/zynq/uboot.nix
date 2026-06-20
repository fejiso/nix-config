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
  # Board select. Use "zynq-zturn-v5" instead for the newer Z-turn board revision.
  extraMakeFlags = [ "DEVICE_TREE=zynq-zturn" ];

  extraMeta.platforms = [ "armv7l-linux" ];
  filesToInstall = [ "spl/boot.bin" "u-boot.img" ];
}
