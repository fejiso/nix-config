{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Platform configuration - CRITICAL for ARM
  nixpkgs.hostPlatform = lib.mkDefault "aarch64-linux";

  # Boot configuration - Amlogic S905X3 uses vendor u-boot
  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = true;

  # Use latest kernel for best Amlogic SM1 device tree support
  boot.kernelPackages = lib.mkDefault pkgs.linuxPackages_latest;

  # Amlogic S905X3 (SM1) device tree
  hardware.deviceTree = {
    enable = true;
    name = "amlogic/meson-sm1-x96-air-gbit.dtb";
    overlays = [
      {
        # Fix memory detection: vendor u-boot reports only 1GB, board has 2GB
        name = "fix-memory";
        dtsText = ''
          /dts-v1/;
          /plugin/;

          / {
            compatible = "amlogic,sm1";
            fragment@0 {
              target-path = "/memory@0";
              __overlay__ {
                reg = <0x0 0x0 0x0 0x80000000>;
              };
            };
          };
        '';
      }
    ];
  };

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

  # Enable redistributable firmware
  hardware.enableRedistributableFirmware = true;
}
