# EliteDX specific home-manager configuration
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

  # Desktop-specific packages
  home.packages = with pkgs; [
    # GUI applications
    firefox
    thunderbird
    discord
    slack
    spotify
    
  ];

  # Desktop-specific services
  services.redshift = {
    enable = true;
    latitude = 40.7;
    longitude = -74.0;
  };

  # GTK theme
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
  };
}
