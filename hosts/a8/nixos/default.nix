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

  
  # Additional server packages
  environment.systemPackages = with pkgs; [
  ];

  # Server-specific services

  services.airspy-adsb = {
    enable = true;
  };
}
