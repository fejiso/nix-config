# EliteDX specific NixOS configuration
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
    # Add any elitedex-specific modules here
  ];

  # Host-specific configuration
  # Add desktop environment if this is a desktop system
  services.xserver = {
    enable = true;
    displayManager.gdm.enable = true;
    desktopManager.gnome.enable = true;
  };

  # Enable additional services for desktop
  services.flatpak.enable = true;
  
  # Host-specific packages
  environment.systemPackages = with pkgs; [
    firefox
    thunderbird
    libreoffice
    gimp
  ];
}
