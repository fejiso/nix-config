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
    ../../../hosts/common/home/development.nix
    ../../../hosts/common/home/desktop.nix
  ];

  # Laptop-specific packages
  home.packages = with pkgs; [
    # CD ripping tools
    cdparanoia
    flac
    cddiscid
    eject
  ];

  # CD ripping script
  home.file.".local/bin/rip-cd" = {
    source = ../../../scripts/rip-cd.sh;
    executable = true;
  };

  

  # Note: upower is a system service, not a home-manager service
  # It should be enabled in the NixOS configuration instead
}
