{ ... }: {
  # Configures home-manager's upstream `programs.hyprlock`.
  #
  # Previously this file declared its OWN `programs.hyprlock` option (clashing
  # with home-manager's built-in module) and was never imported anywhere — so
  # no `~/.config/hypr/hyprlock.conf` was ever generated. hypridle/swayidle
  # still launched `hyprlock`, which bails immediately without a config, so the
  # session never actually locked. (Its old `grace = 300` would also have left a
  # 5-minute window where any input unlocked without a password.)
  flake.modules.homeManager.hyprlock =
  { lib, config, ... }:
  {
    # Auto-enable on Wayland desktops (where hypridle/swayidle drive it).
    # Headless hosts (e.g. hierro) keep their `mkForce false`, which wins.
    programs.hyprlock = {
      enable = lib.mkDefault
        (config.programs.niri.enable or false
          || config.wayland.windowManager.sway.enable or false);

      settings = {
        general = {
          disable_loading_bar = true;
          # No grace period — require the password immediately on lock.
          grace = 0;
          hide_cursor = true;
          no_fade_in = false;
        };

        background = [{
          monitor = "";
          path = "screenshot";
          blur_passes = 3;
          blur_size = 8;
        }];

        input-field = [{
          monitor = "";
          size = "200, 50";
          position = "0, -80";
          dots_center = true;
          fade_on_empty = false;
          font_color = "rgb(202, 211, 245)";
          inner_color = "rgb(91, 96, 120)";
          outer_color = "rgb(24, 25, 38)";
          outline_thickness = 5;
          placeholder_text = "<b>Password...</b>";
          shadow_passes = 2;
        }];
      };
    };
  };
}
