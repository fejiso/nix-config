{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos/nix.nix
    ../../common/nixos/users.nix
    ../../common/nixos/security.nix
    ../../common/nixos/networking.nix
    ../../common/nixos/services.nix
    ../../common/nixos/sops.nix
    ../../common/nixos/distributed-build.nix
    ../../common/nixos/netbird.nix
    (import ../../../modules/nixos/desktop.nix)
    (import ../../../modules/nixos/laptop.nix)
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/7f1bd4db-58b3-40aa-be5c-d38ba434cfcb";
    allowDiscards = true;
  };
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.resumeDevice = "/dev/disk/by-uuid/54cc1038-6f3b-49c0-925b-81ad8127d045";
  boot.kernelParams = [ "resume_offset=533760" ];

  # Swap configuration
  swapDevices = [
    {
      device = "/swapfile";
      size = 18432; # 18GB in MB
    }
  ];

  # Host-specific networking
  networking.hostName = "blacktop";

  # Host-specific services
  services.btrfs.autoScrub.enable = true;

  # System state version
  system.stateVersion = "25.05";
}
