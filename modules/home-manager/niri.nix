{ config, pkgs, lib, ... }:

with lib;

{
  options.programs.niri = {
    enable = mkEnableOption "Niri window manager";
  };

  config = mkIf config.programs.niri.enable {
    home.packages = with pkgs; [ niri waybar brightnessctl wireplumber hyprlock swayidle pavucontrol variety swww xwayland-satellite ];

    services.swayidle = {
      enable = true;
      timeouts = [
        { timeout = 900; command = "${pkgs.hyprlock}/bin/hyprlock"; }
        { timeout = 1800; command = "${pkgs.niri}/bin/niri msg action power-off-monitors"; }
      ];
    };

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

      layout {
          gaps 2
      }

      output "AU Optronics 0xA48F Unknown" {
          position x=1920 y=0
          scale 1.0
          mode "1920x1080@60.049"
      }

      output "PNP(AOC) 24B2W1G5 UOWN41A000261" {
          position x=3840 y=0
          mode "1920x1080@74.973"
      }

      output "PNP(AOC) 27G2G4 GYGM7HA433965" {
          position x=0 y=0
          mode "1920x1080@144.000"
      }

      window-rule {
          match app-id="firefox"
          default-column-width { proportion 1.0; }
          open-on-output "PNP(AOC) 27G2G4 GYGM7HA433965"
          open-maximized true
      }

      window-rule {
          match app-id="strawberry"
          default-column-width { proportion 1.0; }
          open-on-output "PNP(AOC) 24B2W1G5 UOWN41A000261"
          open-on-workspace 2
          open-maximized true
      }

      binds {
          Mod+T { spawn "wezterm"; }
          Mod+Return { spawn "wezterm"; }
          Mod+D { spawn "fuzzel"; }
          Mod+P { spawn "fuzzel"; }
          Mod+Q repeat=false { close-window; }
          
          XF86AudioRaiseVolume allow-when-locked=true { spawn "sh" "-c" "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+"; }
          XF86AudioLowerVolume allow-when-locked=true { spawn "sh" "-c" "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-"; }
          XF86AudioMute        allow-when-locked=true { spawn "sh" "-c" "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"; }
          XF86AudioMicMute     allow-when-locked=true { spawn "sh" "-c" "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }

          XF86AudioPlay        allow-when-locked=true { spawn "sh" "-c" "playerctl play-pause"; }
          XF86AudioStop        allow-when-locked=true { spawn "sh" "-c" "playerctl stop"; }
          XF86AudioPrev        allow-when-locked=true { spawn "sh" "-c" "playerctl previous"; }
          XF86AudioNext        allow-when-locked=true { spawn "sh" "-c" "playerctl next"; }

          XF86MonBrightnessUp allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "+10%"; }
          XF86MonBrightnessDown allow-when-locked=true { spawn "brightnessctl" "--class=backlight" "set" "10%-"; }
          
          Mod+WheelScrollDown cooldown-ms=150 { focus-workspace-down; }
          Mod+WheelScrollUp cooldown-ms=150 { focus-workspace-up; }
          Mod+Ctrl+WheelScrollDown cooldown-ms=150 { move-column-to-workspace-down; }
          Mod+Ctrl+WheelScrollUp cooldown-ms=150 { move-column-to-workspace-up; }

          Mod+WheelScrollRight { focus-column-right; }
          Mod+WheelScrollLeft { focus-column-left; }
          Mod+Ctrl+WheelScrollRight { move-column-right; }
          Mod+Ctrl+WheelScrollLeft { move-column-left; }

          Mod+Shift+WheelScrollDown { focus-column-right; }
          Mod+Shift+WheelScrollUp { focus-column-left; }
          Mod+Ctrl+Shift+WheelScrollDown { move-column-right; }
          Mod+Ctrl+Shift+WheelScrollUp { move-column-left; }
          
          Mod+TouchpadScrollDown { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02+"; }
          Mod+TouchpadScrollUp   { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "0.02-"; }
          
          Mod+Left { focus-column-left; }
          Mod+Down { focus-window-down; }
          Mod+Up { focus-window-up; }
          Mod+Right { focus-column-right; }
          Mod+H { focus-column-left; }
          Mod+J { focus-window-down; }
          Mod+K { focus-window-up; }
          Mod+L { focus-column-right; }
          
          Mod+Shift+Left { focus-monitor-left; }
          Mod+Shift+Down { focus-monitor-down; }
          Mod+Shift+Up { focus-monitor-up; }
          Mod+Shift+Right { focus-monitor-right; }
          Mod+Shift+H { focus-monitor-left; }
          Mod+Shift+J { focus-monitor-down; }
          Mod+Shift+K { focus-monitor-up; }
          Mod+Shift+L { focus-monitor-right; }
          
          Mod+Home { focus-column-first; }
          Mod+End { focus-column-last; }
          Mod+Ctrl+Home { move-column-to-first; }
          Mod+Ctrl+End { move-column-to-last; }
          
          Mod+Shift+Ctrl+Left { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+Down { move-column-to-monitor-down; }
          Mod+Shift+Ctrl+Up { move-column-to-monitor-up; }
          Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
          Mod+Shift+Ctrl+H { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+J { move-column-to-monitor-down; }
          Mod+Shift+Ctrl+K { move-column-to-monitor-up; }
          Mod+Shift+Ctrl+L { move-column-to-monitor-right; }
          
          Mod+1 { focus-workspace 1; }
          Mod+2 { focus-workspace 2; }
          Mod+3 { focus-workspace 3; }
          Mod+4 { focus-workspace 4; }
          Mod+5 { focus-workspace 5; }
          Mod+6 { focus-workspace 6; }
          Mod+7 { focus-workspace 7; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }
          
          Mod+Ctrl+1 { move-column-to-workspace 1; }
          Mod+Ctrl+2 { move-column-to-workspace 2; }
          Mod+Ctrl+3 { move-column-to-workspace 3; }
          Mod+Ctrl+4 { move-column-to-workspace 4; }
          Mod+Ctrl+5 { move-column-to-workspace 5; }
          Mod+Ctrl+6 { move-column-to-workspace 6; }
          Mod+Ctrl+7 { move-column-to-workspace 7; }
          Mod+Ctrl+8 { move-column-to-workspace 8; }
          Mod+Ctrl+9 { move-column-to-workspace 9; }
          
          Mod+Next { focus-workspace-down; }
          Mod+Prior { focus-workspace-up; }
          Mod+U { focus-workspace-down; }
          Mod+I { focus-workspace-up; }
          Mod+Shift+Next { move-workspace-down; }
          Mod+Shift+Prior { move-workspace-up; }
          Mod+Shift+U { move-workspace-down; }
          Mod+Shift+I { move-workspace-up; }
          Mod+Ctrl+Next { move-column-to-workspace-down; }
          Mod+Ctrl+Prior { move-column-to-workspace-up; }
          Mod+Ctrl+U { move-column-to-workspace-down; }
          Mod+Ctrl+I { move-column-to-workspace-up; }
          
          Mod+R { switch-preset-column-width; }
          Mod+F { maximize-column; }
          Mod+Shift+F { fullscreen-window; }
          
          Mod+Ctrl+Left { move-column-left; }
          Mod+Ctrl+Down { move-window-down; }
          Mod+Ctrl+Up { move-window-up; }
          Mod+Ctrl+Right { move-column-right; }
          Mod+Ctrl+H { move-column-left; }
          Mod+Ctrl+J { move-window-down; }
          Mod+Ctrl+K { move-window-up; }
          Mod+Ctrl+L { move-column-right; }
          
          Mod+BracketLeft { consume-or-expel-window-left; }
          Mod+BracketRight { consume-or-expel-window-right; }
          
          Mod+Space { switch-focus-between-floating-and-tiling; }
          Mod+Tab { focus-window-or-workspace-up; }
          Mod+Shift+Tab { focus-window-or-workspace-down; }
          
          Mod+O repeat=false { toggle-overview; }
          Mod+Question { show-hotkey-overlay; }
          
          Mod+Comma { consume-window-into-column; }
          Mod+Period { expel-window-from-column; }
          
          Mod+Shift+R { switch-preset-window-height; }
          Mod+Ctrl+R { reset-window-height; }
          
          Mod+Ctrl+F { expand-column-to-available-width; }
          
          Mod+C { center-column; }
          Mod+Ctrl+C { center-visible-columns; }
          
          Mod+Minus { set-column-width "-10%"; }
          Mod+Equal { set-column-width "+10%"; }
          
          Mod+Shift+Minus { set-window-height "-10%"; }
          Mod+Shift+Equal { set-window-height "+10%"; }
          
          Mod+V { toggle-window-floating; }
          
          Mod+W { toggle-column-tabbed-display; }
          
          Print { screenshot; }
          Ctrl+Print { screenshot-screen; }
          Alt+Print { screenshot-window; }
          
          Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }
          
          Ctrl+Alt+Delete { quit; }
          
          Mod+Shift+P { power-off-monitors; }
          
          Mod+Shift+E { quit; }
      }

      spawn-at-startup "${pkgs.swww}/bin/swww-daemon"
      spawn-at-startup "${pkgs.variety}/bin/variety"
      spawn-at-startup "${pkgs.waybar}/bin/waybar"
      spawn-at-startup "${pkgs.mako}/bin/mako"
      spawn-at-startup "${pkgs.firefox}/bin/firefox"
      spawn-at-startup "${pkgs.strawberry}/bin/strawberry"
      spawn-at-startup "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
    '';
  };
}
