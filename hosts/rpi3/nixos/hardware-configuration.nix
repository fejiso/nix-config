{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Platform configuration - CRITICAL for ARM
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Boot configuration
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Kernel packages provided by nixos-hardware raspberry-pi-3 module

  # File systems - btrfs with compression
  fileSystems."/" = {
    device = "/dev/disk/by-label/NIXOS_SD";
    fsType = "btrfs";
    options = [ "subvol=@" "compress=zstd" "noatime" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/FIRMWARE";
    fsType = "vfat";
  };

  # No swap on SD card (using zram from embedded.nix)
  swapDevices = [ ];

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Enable redistributable firmware (WiFi, Bluetooth)
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];
}
