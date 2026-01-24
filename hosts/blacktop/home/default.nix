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

  # Desktop packages
  home.packages = with pkgs; [
    libreoffice
    zoom-us
  ];
}
