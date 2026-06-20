{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Platform configuration - CRITICAL for ARM
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Boot configuration
  # Pine64 uses latest kernel (no specific kernel package)
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # File systems - btrfs with compression
  # No swap on SD card (using zram from embedded.nix)
  swapDevices = [ ];

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Enable redistributable firmware
  hardware.enableRedistributableFirmware = true;
}
