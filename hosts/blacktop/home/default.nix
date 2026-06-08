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
  ];

  # Disable Sway
  wayland.windowManager.sway.enable = lib.mkForce false;

  # Enable Niri
  programs.niri.enable = true;

  # Bridge desktop audio to the Bose SoundTouch over wifi (select the
  # "Bose SoundTouch" sink, then run `bose-play` / `bose-stop`).
  services.boseSoundtouch.enable = true;

  # Enable TidalCycles
  programs.tidalcycles.enable = true;

  # Enable Android development tools
  programs.android-tools.enable = true;

  # Enable heavy dev tools
  programs.dev-heavy.enable = true;

}
