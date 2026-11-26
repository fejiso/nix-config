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
  ];

  # ADS-B configuration (Hardware support only)
  services.adsb-readsb = {
    enable = false;
    enableRtlSdrHardware = true;
  };

  # Enable development tools
  development.enable = true;

  # Enable emulation
  emulation.enable = true;

  # Zenbook power/fan management: use power-profiles-daemon instead of TLP/asusd
  services.power-profiles-daemon.enable = lib.mkForce true;
  services.tlp.enable = lib.mkForce false;
  systemd.services.power-saver-default = {
    description = "Set default power profile to power-saver";
    after = [ "power-profiles-daemon.service" ];
    requires = [ "power-profiles-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver";
    };
  };

  # Boot & declarative disk layout (LUKS2 + Btrfs @/@home/@nix/@log/@swap via disko)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  boot.loader.systemd-boot.configurationLimit = 3;

  diskoLayout = {
    device = "/dev/nvme0n1";
    swapSize = "18G";
    # After formatting, set resumeOffset for hibernation via:
    #   sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile
    # resumeOffset = ...;
  };

  # Host-specific networking
  networking.hostName = "blacktop";

  # AMD Ryzen 7 4700U (Zen 2 Renoir)
  hardware.cpu.tune = {
    cpu = "znver2";
    group = "x86-64-v3";
  };

  # Tdarr worker node (native NixOS service)
  services.tdarr-worker = {
    enable = true;
  };

  # System state version
  system.stateVersion = "25.05";
}
