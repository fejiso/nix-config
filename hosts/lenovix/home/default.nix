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
  ];

  

  # Note: upower is a system service, not a home-manager service
  # It should be enabled in the NixOS configuration instead
}
