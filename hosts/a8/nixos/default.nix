# A8 specific NixOS configuration (server/headless)
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
  ];

  # Disable graphics (headless server, saves mesa ~500M)
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # AMD A8-7410 APU (Carrizo-L / Puma+ — SSE4.2 + POPCNT + AVX + BMI1 + AES-NI, no AVX2)
  hardware.cpu.tune = {
    cpu = "btver2";
    group = "x86-64-v2";
  };

  # Additional server packages
  environment.systemPackages = with pkgs; [
  ];

  # Server-specific services

  services.airspy-adsb = {
    enable = true;
  };

  # Install-time NixOS release; do not bump on upgrades.
  system.stateVersion = "25.05";
}
