# Hierro home-manager configuration (server)
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

  # Disable desktop/GUI programs for server
  programs.firefox.enable = lib.mkForce false;
  programs.niri.enable = lib.mkForce false;
  programs.tidalcycles.enable = lib.mkForce false;
  programs.hyprlock.enable = lib.mkForce false;
  
  # Disable Wayland window manager
  wayland.windowManager.sway.enable = lib.mkForce false;
  
  # Server-focused packages only
  home.packages = with pkgs; [
    # Remove GUI applications, keep CLI tools
  ] ++ (builtins.filter (pkg: 
    # Filter out GUI applications from common packages
    ! (lib.hasAttr "pname" pkg && builtins.elem pkg.pname [
      "firefox" "strawberry" "localsend" "telegram-desktop"
    ])
  ) config.home.packages);
}