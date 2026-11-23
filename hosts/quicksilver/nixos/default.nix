# Quicksilver specific NixOS configuration (Intel Core 2 Duo SU7300 laptop)
{
  lib,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "quicksilver";
  services.network-watchdog.enable = true;

  # Declarative unencrypted Btrfs layout on /dev/sda with hybrid BIOS+EFI GRUB
  diskoLayout = {
    device = "/dev/sda";
    biosBoot = true;
    swapSize = "8G";
  };

  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "zstd";

  # Intel Core 2 Duo SU7300 (Penryn, SSE4.1 — no SSE4.2/POPCNT/AVX):
  #   - cpu = "core2" tunes host-specific cpuTune packages
  #   - group = null keeps groupTune on stock x86-64 / cache.nixos.org (no SIGILL)
  hardware.cpu.tune = {
    cpu = "core2";
    group = null;
  };

  # Headless/CLI laptop: skip 32-bit Mesa bloat
  hardware.graphics.enable32Bit = lib.mkForce false;

  system.stateVersion = "26.05";
}
