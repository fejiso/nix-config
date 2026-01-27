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
    

    # Music players
    strawberry
    ncspot
    spot

# Music ripping
    whipper
  ];
}
