# Hardware configuration for quicksilver (Intel Core 2 Duo SU7300 laptop).
# Partitioning, Btrfs subvolumes, and swapfile on /dev/sda are managed
# declaratively via `flake-modules/system-modules/disko-btrfs.nix`.
{ config, lib, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Include both AHCI and legacy PIIX IDE + USB 1.1/2.0/3.0 HCDs for Penryn/ICH9M chipsets
  boot.initrd.availableKernelModules = [
    "ahci"
    "ata_piix"
    "uhci_hcd"
    "ehci_pci"
    "xhci_pci"
    "usbhid"
    "usb_storage"
    "sd_mod"
    "sr_mod"
    "sdhci_pci"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-intel" ];
  boot.extraModulePackages = [ ];

  networking.useDHCP = lib.mkDefault true;

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
