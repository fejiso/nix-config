{ ... }: {
  flake.modules.homeManager.noctalia =
  { lib, config, pkgs, ... }:
  let
    wallpaperDir = "~/.local/share/wallpapers/dharmx-walls";
    wallpaperRepo = "https://github.com/dharmx/walls.git";
  in
  {
    systemd.user.services.wallpaper-sync = lib.mkIf config.programs.noctalia.enable {
      Unit = {
        Description = "Sync dharmx/walls wallpaper repository";
      };
      Service = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wallpaper-sync" ''
          DIR="$HOME/.local/share/wallpapers/dharmx-walls"
          mkdir -p "$DIR"
          if [ ! -d "$DIR/.git" ]; then
            ${pkgs.git}/bin/git clone ${wallpaperRepo} "$DIR"
          else
            ${pkgs.git}/bin/git -C "$DIR" pull --ff-only
          fi
        '';
      };
    };

    systemd.user.timers.wallpaper-sync = lib.mkIf config.programs.noctalia.enable {
      Unit.Description = "Sync wallpaper repo daily";
      Timer = {
        OnBootSec = "5min";
        OnUnitActiveSec = "1d";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    programs.noctalia = {
      enable = lib.mkDefault
        (config.programs.niri.enable or false);

      systemd.enable = true;

      settings = {
        shell = {
          font_family = "FiraCode Nerd Font";
          animation = {
            enabled = true;
            speed = 1.0;
          };
          shadow = {
            direction = "down";
            alpha = 0.55;
          };
          panel = {
            transparency_mode = "soft";
            borders = true;
            shadow = true;
          };
          clipboard_enabled = true;
          clipboard_history_max_entries = 100;
        };

        theme = {
          mode = "dark";
          source = "builtin";
          builtin = "Gruvbox";
        };

        wallpaper = {
          enabled = true;
          fill_mode = "crop";
          directory = "~/.local/share/wallpapers/dharmx-walls";
          transition = [ "fade" "wipe" "disc" "stripes" "zoom" "honeycomb" ];
          transition_duration = 1500;
          automation = {
            enabled = true;
            interval_minutes = 30;
            order = "random";
            recursive = true;
          };
        };

        backdrop = {
          enabled = true;
          blur_intensity = 0.5;
          tint_intensity = 0.3;
        };

        notification = {
          enable_daemon = true;
          show_app_name = true;
          show_actions = true;
          layer = "top";
          background_opacity = 0.97;
        };

        osd = {
          position = "top_right";
          orientation = "horizontal";
          background_opacity = 0.97;
        };

        lockscreen = {
          enabled = true;
          blurred_desktop = true;
          blur_intensity = 0.5;
          tint_intensity = 0.3;
        };

        idle = {
          behavior = {
            lock = {
              timeout = 900;
              action = "lock";
              enabled = true;
            };
            screen-off = {
              timeout = 1800;
              # native action powers monitors back on automatically on resume
              action = "screen_off";
              enabled = true;
            };
          };
        };

        system.monitor = {
          enabled = true;
          cpu_poll_seconds = 2.0;
          gpu_poll_seconds = 5.0;
          memory_poll_seconds = 2.0;
          network_poll_seconds = 3.0;
          disk_poll_seconds = 10.0;
        };

        audio = {
          enable_overdrive = false;
          enable_sounds = false;
        };

        bar.main = {
          position = "top";
          thickness = 34;
          background_opacity = 1.0;
          radius = 12;
          margin_h = 180;
          margin_v = 10;
          padding = 14;
          widget_spacing = 6;
          shadow = true;
          reserve_space = true;
          start = [ "launcher" "wallpaper" "workspaces" ];
          center = [ "clock" ];
          end = [ "media" "tray" "notifications" "clipboard" "network" "bluetooth" "volume" "brightness" "battery" "control-center" "session" ];
        };
      };
    };
  };
}
