{ ... }: {
  flake.modules.homeManager.hyprlock =
{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    programs.hyprlock = {
      enable = mkEnableOption "hyprlock";
    };
  };

  config = mkIf config.programs.hyprlock.enable {
    home.packages = with pkgs; [ hyprlock ];

    xdg.configFile."hypr/hyprlock.conf".text = ''
      general {
          disable_loading_bar = true
          grace = 300
          hide_cursor = true
          no_fade_in = false
      }

      background {
          monitor =
          path = screenshot
          blur_passes = 3
          blur_size = 8
      }

      input-field {
          monitor =
          size = 200, 50
          position = 0, -80
          dots_center = true
          fade_on_empty = false
          font_color = rgb(202, 211, 245)
          inner_color = rgb(91, 96, 120)
          outer_color = rgb(24, 25, 38)
          outline_thickness = 5
          placeholder_text = <b>Password...</b>
          shadow_passes = 2
      }
    '';
  };
}
;
}
