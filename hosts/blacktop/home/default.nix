# Blacktop home-manager configuration
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

  # Disable Sway
  wayland.windowManager.sway.enable = lib.mkForce false;
  
  # Niri configuration
  xdg.configFile."niri/config.kdl".text = ''
    input {
        keyboard {
            xkb {
                layout "us,ru"
                variant "altgr-intl,,"
                options "grp:lalt_lshift_toggle"
            }
        }
    }

    spawn-at-startup "waybar"
    spawn-at-startup "mako" 
    spawn-at-startup "kanshi"

    binds {
        Mod+Return { spawn "wezterm"; }
        Mod+Shift+Q { close-window; }
        Mod+P { spawn "fuzzel"; }
        
        Mod+H { focus-column-left; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+L { focus-column-right; }
        
        Mod+Shift+H { move-column-left; }
        Mod+Shift+J { move-window-down; }
        Mod+Shift+K { move-window-up; }
        Mod+Shift+L { move-column-right; }
        
        Mod+1 { focus-workspace 1; }
        Mod+2 { focus-workspace 2; }
        Mod+3 { focus-workspace 3; }
        Mod+4 { focus-workspace 4; }
        Mod+5 { focus-workspace 5; }
        
        Mod+Shift+1 { move-column-to-workspace 1; }
        Mod+Shift+2 { move-column-to-workspace 2; }
        Mod+Shift+3 { move-column-to-workspace 3; }
        Mod+Shift+4 { move-column-to-workspace 4; }
        Mod+Shift+5 { move-column-to-workspace 5; }
        
        Mod+F { fullscreen-window; }
        Mod+Shift+E { quit; }
    }
  '';
}
