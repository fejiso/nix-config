# Hardware configuration for butthead
# This is a placeholder and should be generated/customized based on actual hardware
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

  # Boot configuration - customize based on actual hardware
  boot.initrd.availableKernelModules = [ "xhci_pci" "thunderbolt" "vmd" "nvme" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ]; # or "kvm-amd" for AMD
  boot.extraModulePackages = [ ];

  # Filesystems - TO BE CUSTOMIZED based on actual hardware
  fileSystems."/" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-ROOT-UUID";
    fsType = "ext4";
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/PLACEHOLDER-BOOT-UUID";
    fsType = "vfat";
    options = [ "fmask=0022" "dmask=0022" ];
  };

  # Storage disks for media (examples - customize based on actual setup)
  # fileSystems."/mnt/disk1" = {
  #   device = "/dev/disk/by-uuid/DISK1-UUID";
  #   fsType = "ext4";
  # };
  
  # Swap configuration
  swapDevices = [
    { device = "/swapfile"; size = 32768; } # 32GB swap
  ];

  # Networking
  networking.useDHCP = lib.mkDefault true;

  # Hardware support
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  # hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware; # For AMD
}