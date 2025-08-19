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
      theme = "custom";
      themes.custom.fg = "#ffffff";
      keybinds = {
        
        normal = {
          unbind = ["Alt Left" "Alt Right" "Alt Up" "Alt Down"];
        };
        tab = {
          unbind = ["Ctrl t"];
          bind = {
            "Ctrl y" = { action = { SwitchToMode._args = ["Normal"]; }; };
          };
        };
        pane._children = [
          {
            bind = {
              _args = ["e"];
              _children = [
                { TogglePaneEmbedOrFloating = {}; }
                { SwitchToMode._args = ["locked"]; }
              ];
            };
          }
          {
            bind = {
              _args = ["left"];
              MoveFocus = ["left"];
            };
          }
        ];
        # The original `shared_except` cannot be directly translated to the new format
        # without changing its behavior, as the new `shared_except` structure is different.
        # Please provide guidance on how you'd like to re-implement this logic.
        # Original shared_except:
        # shared_except = [
        #   {
        #     except = ["tab" "locked"];
        #     unbind = ["Ctrl t"];
        #     binds = {
        #       "Ctrl y" = { SwitchToMode = "Tab"; };
        #     };
        #   }
        #   {
        #     except = ["move" "locked"];
        #     unbind = ["Ctrl h"];
        #     binds = {
        #       "Ctrl j" = { SwitchToMode = "Move"; };
        #     };
        #   }
        # ];
      };
    };
  };
}