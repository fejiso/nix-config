{ config, ... }: let
  homeModules = config.flake.modules.homeManager;
in {
  flake.modules.homeManager.desktop =
# Desktop GUI applications
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Media modules live here (not in `default`) so they only land on real
  # desktops — keeps beets/mpd/tidalcycles off devdesktop, work-laptop, amp1.
  imports = [
    homeModules.beets
    homeModules.mpd
    homeModules.tidalcycles
  ];

  home.packages = with pkgs; [
    # GUI development IDEs (moved here from the `development` module so they
    # only land on real desktops, not headless work boxes).
    jetbrains.idea
    postman

    # Desktop applications
    telegram-desktop
    logseq
    libreoffice
    zoom-us
    wine
    
    # Document processing
    texlive.combined.scheme-full

    # Music players
    strawberry
    ncspot
    spot

#ai 
lmstudio

# Music ripping
    whipper
  ];

  # Enable MPD music stack (ncmpcpp + mpd-sima + scrobblers)
  services.mpd-stack = {
    enable = true;
    lastfmUsername = "fjim";
  };
}
;
}
