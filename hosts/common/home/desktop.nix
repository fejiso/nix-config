# Desktop GUI applications
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
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

# Music ripping
    whipper
  ];

  # Enable MPD music stack (ncmpcpp + mpd-sima + scrobblers)
  services.mpd-stack = {
    enable = true;
    lastfmUsername = "fjim";
  };
}
