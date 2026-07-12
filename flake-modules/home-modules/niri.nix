{ ... }: {
  flake.modules.homeManager.niri =
{ config, pkgs, lib, hostname ? "", ... }:

with lib;

{
  options.programs.niri = {
    enable = mkEnableOption "Niri window manager";
  };

  config = mkIf config.programs.niri.enable {
    home.packages = with pkgs; [ niri wireplumber pavucontrol xwayland-satellite wlopm ];

    xdg.configFile."niri/config.kdl".text = ''
      input {
          keyboard {
              xkb {
                  layout "us,ru"
                  variant "altgr-intl,"
                  options "grp:lalt_lshift_toggle,lv3:ralt_switch"
              }
          }

          focus-follows-mouse max-scroll-amount="0%"
      }

      layout {
          gaps 4
          preset-column-widths {
              proportion 0.33333
              proportion 0.5
              proportion 0.66667
          }

          default-column-width { proportion 0.5; }

          preset-window-heights {
              proportion 0.33333
              proportion 0.5
              proportion 0.66667
          }

          focus-ring {
              // off
              // on
              width 4
              active-color "#7fc8ff"
              inactive-color "#505050"
              urgent-color "#9b0000"
              // active-gradient from="#80c8ff" to="#bbddff" angle=45
              // inactive-gradient from="#505050" to="#808080" angle=45 relative-to="workspace-view"
              // urgent-gradient from="#800" to="#a33" angle=45
          }

          border {
              // off
              // on
              width 2
              active-color "#7fc8ff"
              inactive-color "#505050"
              urgent-color "#9b0000"
              // active-gradient from="#ffbb66" to="#ffc880" angle=45 relative-to="workspace-view"
              // inactive-gradient from="#505050" to="#808080" angle=45 relative-to="workspace-view" in="srgb-linear"
              // urgent-gradient from="#800" to="#a33" angle=45
          }

          shadow {
              // off
              // on
              softness 15
              spread 2
              offset x=2 y=3
              draw-behind-window true
              color "#00000040"
              // inactive-color "#00000054"
          }

          tab-indicator {
              // off
              // on
              hide-when-single-tab
              place-within-column
              gap 5
              width 4
              length total-proportion=1.0
              position "right"
              gaps-between-tabs 2
              corner-radius 8
              active-color "red"
              inactive-color "gray"
              urgent-color "blue"
              // active-gradient from="#80c8ff" to="#bbddff" angle=45
              // inactive-gradient from="#505050" to="#808080" angle=45 relative-to="workspace-view"
              // urgent-gradient from="#800" to="#a33" angle=45
          }

          insert-hint {
              // off
              // on
              color "#ffc87f80"
              // gradient from="#ffbb6680" to="#ffc88080" angle=45 relative-to="workspace-view"
          }

          struts {
              // left 64
              // right 64
              // top 64
              // bottom 64
          }
      }

      window-rule {
          geometry-corner-radius 20
          clip-to-geometry true
      }

      window-rule {
          match app-id="dev.noctalia.Noctalia.Settings"
          open-floating true
          default-column-width { fixed 1080; }
          default-window-height { fixed 920; }
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
          open-on-workspace "2"
          open-maximized true
      }

      layer-rule {
          match namespace="^noctalia-backdrop"
          place-within-backdrop true
      }

      debug {
          honor-xdg-activation-with-invalid-serial
      }

      ${if hostname == "butthead" then ''
      // Butthead: Desktop with AOC monitors only
      output "PNP(AOC) 24B2W1G5 UOWN41A000261" {
          position x=1920 y=0
          mode "1920x1080@74.973"
      }

      output "PNP(AOC) 27G2G4 GYGM7HA433965" {
          position x=0 y=0
          mode "1920x1080@144.000"
      }
      '' else ''
      // Blacktop: Laptop with panel + external monitors
      output "Ancor Communications Inc VE248 H3LMQS153004" {
          position x=0 y=0
          mode "1920x1080@60.000"
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
      ''}

      binds {
          Mod+T { spawn "wezterm"; }
          Mod+Return { spawn "wezterm"; }
          Mod+Q repeat=false { close-window; }

          Mod+Space { spawn-sh "noctalia msg panel-toggle launcher"; }
          Mod+D { spawn-sh "noctalia msg panel-toggle launcher"; }
          Mod+P { spawn-sh "noctalia msg panel-toggle launcher"; }
          Mod+S { spawn-sh "noctalia msg panel-toggle control-center"; }
          Mod+Comma { spawn-sh "noctalia msg settings-toggle"; }

          XF86AudioRaiseVolume allow-when-locked=true { spawn-sh "noctalia msg volume-up"; }
          XF86AudioLowerVolume allow-when-locked=true { spawn-sh "noctalia msg volume-down"; }
          XF86AudioMute        allow-when-locked=true { spawn-sh "noctalia msg volume-mute"; }
          XF86AudioMicMute     allow-when-locked=true { spawn "sh" "-c" "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"; }

          XF86AudioPlay        allow-when-locked=true { spawn "sh" "-c" "playerctl play-pause"; }
          XF86AudioStop        allow-when-locked=true { spawn "sh" "-c" "playerctl stop"; }
          XF86AudioPrev        allow-when-locked=true { spawn "sh" "-c" "playerctl previous"; }
          XF86AudioNext        allow-when-locked=true { spawn "sh" "-c" "playerctl next"; }

          XF86MonBrightnessUp   allow-when-locked=true { spawn-sh "noctalia msg brightness-up"; }
          XF86MonBrightnessDown allow-when-locked=true { spawn-sh "noctalia msg brightness-down"; }

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

          // Focus within workspace (columns horizontally)
          Mod+Left { focus-column-left; }
          Mod+Right { focus-column-right; }
          Mod+H { focus-column-left; }
          Mod+L { focus-column-right; }
          Mod+Home { focus-column-first; }
          Mod+End { focus-column-last; }
          Mod+Shift+Semicolon { focus-column-left; }
          Mod+Shift+Slash { focus-column-right; }

          // Move within workspace (columns horizontally)
          Mod+Ctrl+Left { move-column-left; }
          Mod+Ctrl+Right { move-column-right; }
          Mod+Ctrl+H { move-column-left; }
          Mod+Ctrl+L { move-column-right; }
          Mod+Ctrl+Home { move-column-to-first; }
          Mod+Ctrl+End { move-column-to-last; }
          Mod+Ctrl+Shift+Semicolon { move-column-left; }
          Mod+Ctrl+Shift+Slash { move-column-right; }

          // Focus workspace (up/down navigation)
          Mod+Down { focus-workspace-down; }
          Mod+Up { focus-workspace-up; }
          Mod+J { focus-workspace-down; }
          Mod+K { focus-workspace-up; }
          Mod+U { focus-workspace-down; }
          Mod+I { focus-workspace-up; }
          Mod+Next { focus-workspace-down; }
          Mod+Prior { focus-workspace-up; }

          // Move to workspace (up/down navigation)
          Mod+Ctrl+Down { move-column-to-workspace-down; }
          Mod+Ctrl+Up { move-column-to-workspace-up; }
          Mod+Ctrl+J { move-column-to-workspace-down; }
          Mod+Ctrl+K { move-column-to-workspace-up; }
          Mod+Ctrl+U { move-column-to-workspace-down; }
          Mod+Ctrl+I { move-column-to-workspace-up; } Mod+Ctrl+Next { move-column-to-workspace-down; }
          Mod+Ctrl+Prior { move-column-to-workspace-up; }

          // Focus monitor (horizontal only)
          Mod+Shift+Left { focus-monitor-left; }
          Mod+Shift+Right { focus-monitor-right; }
          Mod+Shift+H { focus-monitor-left; }
          Mod+Shift+L { focus-monitor-right; }

          // Move to monitor (horizontal only)
          Mod+Shift+Ctrl+Left { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+Right { move-column-to-monitor-right; }
          Mod+Shift+Ctrl+H { move-column-to-monitor-left; }
          Mod+Shift+Ctrl+L { move-column-to-monitor-right; }

          // Focus workspace (by number)
          Mod+1 { focus-workspace 1; }
          Mod+2 { focus-workspace 2; }
          Mod+3 { focus-workspace 3; }
          Mod+4 { focus-workspace 4; }
          Mod+5 { focus-workspace 5; }
          Mod+6 { focus-workspace 6; }
          Mod+7 { focus-workspace 7; }
          Mod+8 { focus-workspace 8; }
          Mod+9 { focus-workspace 9; }

          // Move to workspace (by number)
          Mod+Ctrl+1 { move-column-to-workspace 1; }
          Mod+Ctrl+2 { move-column-to-workspace 2; }
          Mod+Ctrl+3 { move-column-to-workspace 3; }
          Mod+Ctrl+4 { move-column-to-workspace 4; }
          Mod+Ctrl+5 { move-column-to-workspace 5; }
          Mod+Ctrl+6 { move-column-to-workspace 6; }
          Mod+Ctrl+7 { move-column-to-workspace 7; }
          Mod+Ctrl+8 { move-column-to-workspace 8; }
          Mod+Ctrl+9 { move-column-to-workspace 9; }

          // Move workspace itself (reorder workspaces)
          Mod+Shift+Next { move-workspace-down; }
          Mod+Shift+Prior { move-workspace-up; }
          Mod+Shift+U { move-workspace-down; }
          Mod+Shift+I { move-workspace-up; }

          Mod+R { switch-preset-column-width; }
          Mod+F { maximize-column; }
          Mod+Shift+F { fullscreen-window; }

          Mod+BracketLeft { consume-or-expel-window-left; }
          Mod+BracketRight { consume-or-expel-window-right; }

          Mod+Tab { focus-window-or-workspace-up; }
          Mod+Shift+Tab { focus-window-or-workspace-down; }

          Mod+O repeat=false { toggle-overview; }
          Mod+Question { show-hotkey-overlay; }

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

          Mod+Alt+W { toggle-column-tabbed-display; }

          Print { screenshot; }
          Ctrl+Alt+Print { screenshot; }
          Ctrl+Print { screenshot-screen; }
          Alt+Print { screenshot-window; }

          Mod+Escape allow-inhibiting=false { toggle-keyboard-shortcuts-inhibit; }

          Ctrl+Alt+Delete { spawn-sh "noctalia msg session lock"; }
          Mod+Shift+Q { spawn-sh "noctalia msg session lock"; }
          Mod+Ctrl+Q { spawn-sh "noctalia msg session lock"; }

          Mod+Shift+P { power-off-monitors; }

          Mod+Shift+E { quit; }
      }

      spawn-at-startup "noctalia" "--daemon"
      spawn-at-startup "${pkgs.firefox}/bin/firefox"
      spawn-at-startup "${pkgs.strawberry}/bin/strawberry"
      spawn-at-startup "${pkgs.xwayland-satellite}/bin/xwayland-satellite"
      spawn-at-startup "${pkgs.telegram-desktop}/bin/Telegram"
      spawn-at-startup "${pkgs.spotify}/bin/spotify"
      spawn-at-startup "steam"
      spawn-at-startup "sleep 1 && ${pkgs.niri}/bin/niri msg output \"Ancor Communications Inc VE248 H3LMQS153004\" position set 0 0"
      spawn-at-startup "sleep 1 && ${pkgs.niri}/bin/niri msg output \"AU Optronics 0xA48F Unknown\" position set 1920 0"
    '';
  };
}
;
}
