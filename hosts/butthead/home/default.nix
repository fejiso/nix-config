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
    ../../common/home/development.nix
    ../../common/home/desktop.nix
  ];

  # Enable desktop programs (shares config with blacktop)
  programs.niri.enable = true;

  # Enable Android development tools
  programs.android-tools.enable = true;

  # Enable heavy dev tools
  programs.dev-heavy.enable = true;

  # Media server specific applications
  home.packages = with pkgs; [
    # Media management tools
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