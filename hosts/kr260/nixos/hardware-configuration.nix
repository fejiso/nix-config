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
  # KR260 revB (board silkscreen "REV B01"; u-boot reports "Model: ZynqMP KR260
  # revB", FRU SOM "SMK-K26-XCL2G rev1" + carrier "SCK-KR-G rev1"). linux-xlnx's
  # DT naming predates the "rev1" FRU labels: it has only `smk-k26-revA` SOMs
  # (no revB SOM in this tree) with carrier `sck-kr-g-revA`/`-revB`. So: SOM
  # revA, carrier revB. (Verified present in the built kernel's dtbs/.)
  hardware.deviceTree.name = "xilinx/zynqmp-smk-k26-revA-sck-kr-g-revB.dtb";

  # Root filesystem (btrfs, grow-on-boot) and the FAT boot partition come from
  # the shared sd-image-btrfs module (wired in by mk-host for sdImage hosts).

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
}
