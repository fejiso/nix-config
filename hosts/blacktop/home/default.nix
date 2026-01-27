# Blacktop home-manager configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ../../common/home
    ../../common/home/development.nix
    ../../common/home/desktop.nix
  ];

  # Disable Sway
  wayland.windowManager.sway.enable = lib.mkForce false;

  # Enable Niri
  programs.niri.enable = true;

  # Enable TidalCycles
  programs.tidalcycles.enable = true;

  # Enable Android development tools
  programs.android-tools.enable = true;

  # Enable heavy dev tools
  programs.dev-heavy.enable = true;

}
