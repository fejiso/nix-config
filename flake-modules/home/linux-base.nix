{ ... }: {
  flake.modules.homeManager.linux-default = { lib, config, pkgs, ... }: {
    # Linux-only CLI tools that previously lived in the cross-platform default.
    home.packages = with pkgs; [
      lshw
      pciutils
      e2fsprogs # badblocks
    ];

    services.mako.enable = true;

    services.swayidle = lib.mkIf (!config.programs.niri.enable) {
      enable = true;
      events = {
        before-sleep = "${pkgs.hyprlock}/bin/hyprlock";
      };
      timeouts = [
        {
          timeout = 600;
          command = "${pkgs.hyprlock}/bin/hyprlock";
        }
        {
          timeout = 900;
          command = "swaymsg 'output * dpms off'";
          resumeCommand = "swaymsg 'output * dpms on'";
        }
      ];
    };

    programs.waybar = {
      enable = true;
      settings = {
        mainBar = {
          height = 30;
          spacing = 4;
          modules-left = [ "niri/workspaces" "custom/media" ];
          modules-center = [ "niri/window" ];
          modules-right = [ "idle_inhibitor" "pulseaudio" "network" "cpu" "memory" "temperature" "backlight" "battery" "clock" "tray" ];

          "niri/workspaces" = {
            format = "{name}";
          };

          "niri/window" = {
            format = "{}";
            max-length = 50;
          };

          "keyboard-state" = {
            numlock = true;
            capslock = true;
            format = "{name} {icon}";
            format-icons = {
              locked = "";
              unlocked = "";
            };
          };

          "idle_inhibitor" = {
            format = "{icon}";
            format-icons = {
              activated = "";
              deactivated = "";
            };
          };

          tray = {
            spacing = 10;
          };

          clock = {
            tooltip-format = "<big>{:%Y %B}</big>\n<tt><small>{calendar}</small></tt>";
            format-alt = "{:%Y-%m-%d}";
          };

          cpu = {
            format = "{usage}% ";
            tooltip = false;
          };

          memory = {
            format = "{}% ";
          };

          temperature = {
            critical-threshold = 80;
            format = "{temperatureC}°C {icon}";
            format-icons = [ "" "" "" ];
          };

          backlight = {
            format = "{percent}% {icon}";
            format-icons = [ "" "" "" "" "" "" "" "" "" ];
          };

          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{capacity}% {icon}";
            format-charging = "{capacity}% ";
            format-plugged = "{capacity}% ";
            format-alt = "{time} {icon}";
            format-icons = [ "" "" "" "" "" ];
          };

          network = {
            format-wifi = "{essid} ({signalStrength}%) ";
            format-ethernet = "{ipaddr}/{cidr} ";
            tooltip-format = "{ifname} via {gwaddr} ";
            format-linked = "{ifname} (No IP) ";
            format-disconnected = "Disconnected ⚠";
            format-alt = "{ifname}: {ipaddr}/{cidr}";
          };

          pulseaudio = {
            format = "{volume}% {icon} {format_source}";
            format-bluetooth = "{volume}% {icon} {format_source}";
            format-bluetooth-muted = " {icon} {format_source}";
            format-muted = " {format_source}";
            format-source = "{volume}% ";
            format-source-muted = "";
            format-icons = {
              headphone = "";
              hands-free = "";
              headset = "";
              phone = "";
              portable = "";
              car = "";
              default = [ "" "" "" ];
            };
            on-click = "pavucontrol";
          };

          "custom/media" = {
            format = "{icon} {}";
            return-type = "json";
            max-length = 40;
            format-icons = {
              clementine = "";
              default = "🎜";
            };
            escape = true;
          };
        };
      };
    };
  };
}
