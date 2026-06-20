{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Platform configuration - CRITICAL for ARM
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Boot configuration
  # Kernel packages provided by nixos-hardware raspberry-pi-3 module

  # File systems - btrfs with compression
  # No swap on SD card (using zram from embedded.nix)
  swapDevices = [ ];

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Enable redistributable firmware (WiFi, Bluetooth)
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];
}
