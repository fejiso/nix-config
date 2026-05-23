# Hierro home-manager configuration (server)
{ inputs, outputs, lib, config, pkgs, ... }: {
  # Disable desktop/GUI programs for server
  programs.firefox.enable = lib.mkForce false;
  programs.niri.enable = lib.mkForce false;
  programs.tidalcycles.enable = lib.mkForce false;
  programs.hyprlock.enable = lib.mkForce false;
  
  # Disable Wayland window manager
  wayland.windowManager.sway.enable = lib.mkForce false;
  
  # Server-focused packages only - inherit from common but filter out GUI apps
  home.packages = with pkgs; [
    # CLI tools only for server
  ];
}