# Home manager configuration for butthead
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
    ../../common/home
  ];

  # Enable desktop programs (shares config with blacktop)
  programs.niri.enable = true;

  # Media server specific applications
  home.packages = with pkgs; [
    # Media management tools
    jellyfin-media-player
    vlc
    
    # System monitoring for server
    htop
    iotop
    nethogs
    
    # Container management tools
    podman-tui
  ];

  # Home Manager state version
  home.stateVersion = "25.05";
}