{ config, pkgs, ... }:

{
  programs.zellij.enable = true;
  
  home.file.".config/zellij/config.kdl".text = ''
    scroll_buffer_size 100000

    ui {
        pane_frames {
                    rounded_corners true
        }
    }

    keybinds {
        normal {
            // used for moving in fish, hjkl is enough
            unbind "Alt Left"
            unbind "Alt Right"
            unbind "Alt Up"
            unbind "Alt Down"
        }
        tab {
            // used for fzf in fish
           unbind "Ctrl t"
           bind "Ctrl y" { SwitchToMode "Normal"; }
        }
        shared_except "tab" "locked" {
            // used for fzf in fish
           unbind "Ctrl t"
           bind "Ctrl y" { SwitchToMode "Tab"; }
        }
        shared_except "move" "locked" {
            // collides with ctrl+backspace
            unbind "Ctrl h"
            bind "Ctrl j" { SwitchToMode "Move"; }
        }
    }
  '';
}