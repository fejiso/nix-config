# Lenovix specific home-manager configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../../hosts/common/home
  ];

  # Laptop-specific packages
  home.packages = with pkgs; [
    # GUI applications
    firefox
    thunderbird
    
    # Laptop utilities
    brightnessctl
    playerctl
  ];

  # Laptop-specific services
  services.redshift = {
    enable = true;
    latitude = 40.7;
    longitude = -74.0;
  };

  # Note: upower is a system service, not a home-manager service
  # It should be enabled in the NixOS configuration instead
}
