{ config, pkgs, ... }:

{
  programs.zellij = {
    enable = true;
    settings = {
      scroll_buffer_size = 100000;
      ui = {
        pane_frames = {
          rounded_corners = true;
        };
      };
      keybinds = {
        normal = {
          unbind = ["Alt Left" "Alt Right" "Alt Up" "Alt Down"];
        };
        tab = {
          unbind = ["Ctrl t"];
          bind = {
            "Ctrl y" = { SwitchToMode = "Normal"; };
          };
        };
        shared_except = [
          {
            except = ["tab" "locked"];
            unbind = ["Ctrl t"];
            binds = {
              "Ctrl y" = { SwitchToMode = "Tab"; };
            };
          }
          {
            except = ["move" "locked"];
            unbind = ["Ctrl h"];
            binds = {
              "Ctrl j" = { SwitchToMode = "Move"; };
            };
          }
        ];
      };
    };
  };
}