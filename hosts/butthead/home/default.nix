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
  ];

  # Enable desktop programs (shares config with blacktop)
  programs.niri.enable = true;

  # DLNA audio bridge (pa-dlna): the Bose SoundTouch shows up as a PipeWire sink.
  services.boseSoundtouch.enable = true;
  # NB: the soundcork cloud-replacement server is a *system* service, enabled in
  # hosts/butthead/nixos/default.nix (services.soundcork), not here.

  # Enable Android development tools
  programs.android-tools.enable = true;

  # Enable heavy dev tools
  programs.dev-heavy.enable = true;

  # Enable TidalCycles
  programs.tidalcycles.enable = true;

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