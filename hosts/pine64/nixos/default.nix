{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  # Host identification
  networking.hostName = "pine64";

  # Enable embedded optimizations for resource-constrained device
  embedded = {
    enable = true;
    serialConsole = "ttyS0";  # Pine64 serial console
  };

  # Enable automatic ext4 to btrfs conversion on first boot
  services.btrfs-convert-firstboot = {
    enable = true;
    rootDevice = "/dev/disk/by-label/NIXOS_SD";
    subvolume = "@";
  };

  # Disable x86-specific graphics - causes issues with Intel packages on ARM
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # Disable systemd-boot (x86_64 UEFI) - ARM uses generic-extlinux-compatible
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # NixOS version inherited from common/nixos
}
