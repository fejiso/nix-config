{ lib, pkgs, ... }:

{
  # 32-bit ARM (Zynq-7020 Cortex-A9). Cross-compile: build on x86, target armv7l.
  # No native armv7l builder and the repo avoids QEMU binfmt, so everything is
  # produced as ordinary x86 derivations emitting armv7l output.
  nixpkgs.hostPlatform  = lib.mkDefault "armv7l-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # linux-xlnx (Xilinx fork) — overrides the sd-image module's linuxPackages_latest.
  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor pkgs.linuxZynqXlnx);

  # The SD-image profile pulls in nixos all-hardware.nix, whose broad
  # availableKernelModules list (Allwinner pwm-sun4i, etc.) isn't in the Zynq
  # xlnx kernel and breaks modules-shrunk. The board's MMC/SDHCI/btrfs drivers
  # are builtin, so no initrd device modules are needed.
  boot.initrd.availableKernelModules = lib.mkForce [ ];

  hardware.deviceTree.enable = true;
  # linux-xlnx installs the Zynq DTBs flat. Use "zynq-zturn-v5.dtb" for the
  # newer board revision.
  hardware.deviceTree.name = "zynq-zturn.dtb";

  # Root filesystem (btrfs, grow-on-boot) and the FAT boot partition come from
  # the shared sd-image-btrfs module (wired in by mk-host for sdImage hosts).

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
}
