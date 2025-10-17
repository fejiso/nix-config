{ config, pkgs, lib, ... }:

with lib;

{
  options.programs.niri = {
    enable = mkEnableOption "Niri window manager";
  };

  config = mkIf config.programs.niri.enable {
    home.packages = with pkgs; [ niri ];

    xdg.configFile."niri/config.kdl".text = ''
      input {
          keyboard {
              xkb {
                  layout "us,ru"
                  variant "altgr-intl,,"
                  options "grp:lalt_lshift_toggle"
              }
          }
      }

      spawn-at-startup "waybar"
    '';
  };
}
