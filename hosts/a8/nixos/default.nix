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
