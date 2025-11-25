{ config, pkgs, ... }:

{
  programs.wezterm = {
    enable = true;
    extraConfig = ''
      local config = wezterm.config_builder()
      
      config.font = wezterm.font("Fira Code")
      config.font_size = 12.0
      config.window_background_opacity = 0.8
      config.text_background_opacity = 1.0
      ${if pkgs.stdenv.isLinux then "config.enable_wayland = true" else ""}
      config.window_decorations = "NONE"
    
      ${if pkgs.stdenv.isLinux then ''
      -- Clipboard configuration for Linux/Wayland
      config.keys = {
        {
          key = 'c',
          mods = 'CTRL|SHIFT',
          action = wezterm.action.CopyTo 'ClipboardAndPrimarySelection',
        },
        {
          key = 'v',
          mods = 'CTRL|SHIFT',
          action = wezterm.action.PasteFrom 'Clipboard',
        },
      }
      '' else ""}
      
      -- Ensure transparency works with Wayland compositors
      config.front_end = "OpenGL"
      
      config.mux_enable_ssh_agent = false
      
      return config
    '';
  };
}
