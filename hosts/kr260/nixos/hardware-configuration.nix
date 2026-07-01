{ lib, pkgs, ... }:

{
  # 64-bit ARM (Xilinx Zynq UltraScale+ ZU2EG, Cortex-A53). Cross-compile: build
  # on x86, target aarch64. Pure cross (no QEMU binfmt), so everything is
  # produced as ordinary x86 derivations emitting aarch64 output — same model as
  # z-turn (the repo routes aarch64 via amp1 OR cross; kr260 picks cross).
  nixpkgs.hostPlatform  = lib.mkDefault "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # linux-xlnx (Xilinx fork, ZynqMP) — overrides the sd-image module's
  # linuxPackages_latest.
  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor pkgs.linuxZynqmpXlnx);

  # The SD-image profile pulls in nixos all-hardware.nix, whose broad
  # availableKernelModules list (Allwinner pwm-sun4i, etc.) isn't in the ZynqMP
  # xlnx kernel and breaks modules-shrunk. The board's MMC/SDHCI/btrfs drivers
  # are builtin, so no initrd device modules are needed.
  boot.initrd.availableKernelModules = lib.mkForce [ ];

  hardware.deviceTree.enable = true;
  # KR260 starter kit = K26 SOM (revB) on the KR260 carrier (revA).
  # linux-xlnx installs the ZynqMP DTBs under xilinx/. Adjust the carrier-rev
  # suffix (-revA/-revB/-g) to match your board if this DT is absent.
  hardware.deviceTree.name = "xilinx/zynqmp-smk-k26-revB-sck-kr-g-revA.dtb";

  # Root filesystem (btrfs, grow-on-boot) and the FAT boot partition come from
  # the shared sd-image-btrfs module (wired in by mk-host for sdImage hosts).

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
}
