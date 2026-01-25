# Snuffles specific home-manager configuration
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

  # ADS-B feeder specific packages
  home.packages = with pkgs; [
  ];
}
