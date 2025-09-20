{ config, pkgs, lib, ... }:

{
  wayland.windowManager.sway = {
    enable = true;
    package = if (lib.hasAttr "nixos" config.targets) then pkgs.sway else null;
    config = {
      modifier = "Mod4";
      terminal = "wezterm";
      menu = "bemenu-run --fn $uifont -b -p \"▶\" --tf \"$prompt\" --hf \"$highlight\" --sf \"$highlight\" --scf \"$highlight\" | xargs swaymsg exec";
      output = {
        "*" = {
          bg = "${pkgs.sway}/share/backgrounds/sway/Sway_Wallpaper_Blue_1920x1080.png fill";
        };
      };
      input = {
        "*" = {
          xkb_layout = "us,ru";
          xkb_variant = "altgr-intl,,";
          xkb_options = "grp:lalt_lshift_toggle";
        };
      };
      keybindings = {
        "Mod4+Return" = "exec $term";
        "Mod4+Shift+q" = "kill";
        "Mod4+p" = "exec $menu";
        "Mod4+Shift+c" = "reload";
        "Mod4+Shift+e" = "exec swaynag -t warning -m 'You pressed the exit shortcut. Do you really want to exit sway? This will end your Wayland session.' -b 'Yes, exit sway' 'swaymsg exit'";
        "Mod4+h" = "focus left";
        "Mod4+j" = "focus down";
        "Mod4+k" = "focus up";
        "Mod4+l" = "focus right";
        "Mod4+Left" = "focus left";
        "Mod4+Down" = "focus down";
        "Mod4+Up" = "focus up";
        "Mod4+Right" = "focus right";
        "Mod4+Shift+h" = "move left";
        "Mod4+Shift+j" = "move down";
        "Mod4+Shift+k" = "move up";
        "Mod4+Shift+l" = "move right";
        "Mod4+Shift+Left" = "move left";
        "Mod4+Shift+Down" = "move down";
        "Mod4+Shift+Up" = "move up";
        "Mod4+Shift+Right" = "move right";
        "Mod4+1" = "workspace 1";
        "Mod4+2" = "workspace 2";
        "Mod4+3" = "workspace 3";
        "Mod4+4" = "workspace 4";
        "Mod4+5" = "workspace 5";
        "Mod4+6" = "workspace 6";
        "Mod4+7" = "workspace 7";
        "Mod4+8" = "workspace 8";
        "Mod4+9" = "workspace 9";
        "Mod4+0" = "workspace 10";
        "Mod4+Shift+1" = "move container to workspace 1";
        "Mod4+Shift+2" = "move container to workspace 2";
        "Mod4+Shift+3" = "move container to workspace 3";
        "Mod4+Shift+4" = "move container to workspace 4";
        "Mod4+Shift+5" = "move container to workspace 5";
        "Mod4+Shift+6" = "move container to workspace 6";
        "Mod4+Shift+7" = "move container to workspace 7";
        "Mod4+Shift+8" = "move container to workspace 8";
        "Mod4+Shift+9" = "move container to workspace 9";
        "Mod4+Shift+0" = "move container to workspace 10";
        "Mod4+b" = "splith";
        "Mod4+v" = "splitv";
        "Mod4+s" = "layout stacking";
        "Mod4+w" = "layout tabbed";
        "Mod4+e" = "layout toggle split";
        "Mod4+f" = "fullscreen";
        "Mod4+Shift+space" = "floating toggle";
        "Mod4+space" = "focus mode_toggle";
        "Mod4+tab" = "workspace next_on_output";
        "Mod4+a" = "focus parent";
        "Mod4+Shift+minus" = "move scratchpad";
        "Mod4+minus" = "scratchpad show";
        "Mod4+r" = "mode resize";
      };
      modes = {
        resize = {
          "h" = "resize shrink width 10px";
          "j" = "resize grow height 10px";
          "k" = "resize shrink height 10px";
          "l" = "resize grow width 10px";
          "Left" = "resize shrink width 10px";
          "Down" = "resize grow height 10px";
          "Up" = "resize shrink height 10px";
          "Right" = "resize grow width 10px";
          "Return" = "mode default";
          "Escape" = "mode default";
        };
      };
      workspaceOutputAssign = [
        { workspace = "1"; output = "DP-3"; }
        { workspace = "2"; output = "eDP-1"; }
        { workspace = "3"; output = "HDMI-A-1"; }
        { workspace = "4"; output = "DP-3"; }
        { workspace = "5"; output = "eDP-1"; }
        { workspace = "6"; output = "HDMI-A-1"; }
        { workspace = "7"; output = "DP-3"; }
        { workspace = "8"; output = "eDP-1"; }
        { workspace = "9"; output = "HDMI-A-1"; }
        { workspace = "10"; output = "DP-3"; }
      ];
    };
    extraConfig = ''
      bar swaybar_command waybar
      exec swayidle -w \
               timeout 600 'swaylock -f -c 000000' \
               timeout 900 'swaymsg "output * dpms off"' \
                    resume 'swaymsg "output * dpms on"' \
               before-sleep 'swaylock -f -c 000000' &
      exec mako &
      exec kanshi &
      floating_modifier Mod4 normal
    '';
    wrapperFeatures = {
      base = true;
      gtk = true;
    };
  };
}
