{ ... }: {
  flake.modules.homeManager.ghostty =
{ pkgs, ... }:

{
  programs.ghostty = {
    enable = true;
    settings = {
      font-family = "Fira Code";
      theme = "Cobalt Dark Next";
      font-size = 8;
/*    background-opacity = 0.8; */
      window-decoration = "none";
      keybind = if pkgs.stdenv.isLinux then [
        "ctrl+shift+c=copy_to_clipboard:mixed"
        "ctrl+shift+v=paste_from_clipboard"
        "shift+enter=csi:13;2u"
        "alt+enter=esc:\\r"
        "ctrl+f11=toggle_fullscreen"
      ] else [ ];
    };
  };
}
;
}
