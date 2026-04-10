# Hardware configuration for butthead
# This is a placeholder and should be generated/customized based on actual hardware
{ config, lib, pkgs, modulesPath, ... }:

{
  imports =
    [ (modulesPath + "/installer/scan/not-detected.nix")
    ];

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  boot.initrd.kernelModules = [ "amdgpu" ];
  boot.kernelModules = [ "kvm-amd" "nct6687d" ];
  boot.extraModulePackages = with config.boot.kernelPackages; [ nct6687d ];

  fileSystems."/" =
    { device = "/dev/mapper/crypted";
      fsType = "btrfs";
      options = [ "subvol=@" "degraded" "compress=lzo" "noatime" ];
    };

  boot.initrd.luks.devices."crypted" = {
    device = "/dev/disk/by-uuid/1d7380f8-9909-4f68-9e1d-c9f48e0dcba4";
    keyFile = "/luks-key";
  };

  # Copy the keyfile from /boot into the initrd
  boot.initrd.secrets = {
    "/luks-key" = "/boot/luks-key";
  };

  fileSystems."/home" =
    { device = "/dev/mapper/crypted";
      fsType = "btrfs";
      options = [ "subvol=@home" "degraded" "compress=lzo" "noatime" ];
    };

  fileSystems."/nix" =
    { device = "/dev/mapper/crypted";
      fsType = "btrfs";
      options = [ "subvol=@nix" "degraded" "compress=lzo" "noatime" ];
    };

  fileSystems."/var/log" =
    { device = "/dev/mapper/crypted";
      fsType = "btrfs";
      options = [ "subvol=@log" "degraded" "compress=lzo" "noatime" ];
    };

  fileSystems."/boot" =
    { device = "/dev/disk/by-uuid/6B41-D58D";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

  # swapDevices configured in default.nix for hibernation support

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
