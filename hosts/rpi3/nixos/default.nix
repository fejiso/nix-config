{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos
    ../../../modules/nixos/embedded.nix
    inputs.nixos-hardware.nixosModules.raspberry-pi-3
  ];

  # Host identification
  networking.hostName = "rpi3";

  # Enable embedded optimizations for resource-constrained device
  embedded = {
    enable = true;
    serialConsole = "ttyAMA0";  # Raspberry Pi 3 serial console
  };

  # Disable x86-specific graphics - causes issues with Intel packages on ARM
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # Disable systemd-boot (x86_64 UEFI) - ARM uses generic-extlinux-compatible
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # NixOS version inherited from common/nixos
}
