{ config, pkgs, ... }:

{
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      config.font = wezterm.font("Fira Code")
      config.font_size = 12.0
      config.window_background_opacity = 0.8
      config.text_background_opacity = 1.0
      config.enable_wayland = true
      config.window_decorations = "RESIZE"
    '';
  };
}