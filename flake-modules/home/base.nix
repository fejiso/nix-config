{ ... }: {
  flake.modules.homeManager.default = { inputs, outputs, lib, config, pkgs, hostname, ... }: {
    home = {
      enableNixpkgsReleaseCheck = false;
    };

    home.packages = with pkgs; [
      htop btop tree pstree wget curl unzip zip jq ripgrep fd bat eza zoxide broot fzf nmap
      zellij fish weechat
      git git-annex gh direnv colmena
      vim nano
      lshw jq pciutils
      f3
      e2fsprogs # badblocks
      mtr pfetch hyfetch fastfetch iperf3 rclone
      git-filter-repo git-crypt
      nil nix nix-index nixd rmlint age sops
    ];

    programs.home-manager.enable = true;

    services.syncthing = {
      enable = true;
    };

    services.mako.enable = true;

    services.swayidle = lib.mkIf (!config.programs.niri.enable) {
      enable = true;
      events = [
        { event = "before-sleep"; command = "${pkgs.hyprlock}/bin/hyprlock"; }
      ];
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

    xdg.enable = true;

    home.stateVersion = "25.05";

    home.sessionVariables = {
      GNUPGHOME = "${config.home.homeDirectory}/.gnupg";
    };

    sops = {
      age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";
      defaultSopsFile = "${inputs.self}/secrets/secrets.yaml";
      validateSopsFiles = false;

      secrets = {
        git-credentials = {
          sopsFile = "${inputs.self}/secrets/git-credentials-age.yaml";
          key = "git_credentials";
          path = "${config.home.homeDirectory}/.git-credentials";
          mode = "0600";
        };
        acoustid-apikey = {
          sopsFile = "${inputs.self}/secrets/beets.yaml";
          key = "acoustid_apikey";
        };
        lastfm-password = {
          sopsFile = "${inputs.self}/secrets/music.yaml";
          key = "lastfm_password_hash";
        };
        listenbrainz-token = {
          sopsFile = "${inputs.self}/secrets/music.yaml";
          key = "listenbrainz_token";
        };
        atuin-key = {
          sopsFile = "${inputs.self}/secrets/atuin.yaml";
          key = "atuin_key";
          path = "${config.home.homeDirectory}/.local/share/atuin/key";
          mode = "0600";
        };
      };
    };
  };
}
