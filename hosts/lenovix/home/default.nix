# Lenovix specific home-manager configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # Laptop-specific packages
  home.packages = with pkgs; [
  ];
}
