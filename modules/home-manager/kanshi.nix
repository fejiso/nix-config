{ config, pkgs, ... }:

{
  services.kanshi = {
    enable = true;
    settings = [
      {
        profile = {
          name = "laptop";
          outputs = [
            { criteria = "LVDS-1"; status = "enable"; scale = 2.0; }
          ];
        };
      }
      {
        profile = {
          name = "docked";
          outputs = [
            { criteria = "LVDS-1"; status = "disable"; }
            { criteria = "Some Company ASDF 4242"; status = "enable"; mode = "1600x900"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_only";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_and_HDMI-A-1";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "0,0"; }
            { criteria = "HDMI-A-1"; status = "enable"; position = "1920,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_and_DP-1";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "DP-1"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_and_DP-2";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "DP-2"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_and_DP-3";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "DP-3"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "eDP-1_and_DP-4";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "DP-4"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "triple_monitor_1";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "HDMI-A-1"; status = "enable"; position = "3840,0"; }
            { criteria = "DP-1"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "triple_monitor_2";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "HDMI-A-1"; status = "enable"; position = "3840,0"; }
            { criteria = "DP-2"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "triple_monitor_3";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "HDMI-A-1"; status = "enable"; position = "3840,0"; }
            { criteria = "DP-3"; status = "enable"; position = "0,0"; }
          ];
        };
      }
      {
        profile = {
          name = "triple_monitor_4";
          outputs = [
            { criteria = "eDP-1"; status = "enable"; position = "1920,0"; }
            { criteria = "HDMI-A-1"; status = "enable"; position = "3840,0"; }
            { criteria = "DP-4"; status = "enable"; position = "0,0"; }
          ];
        };
      }
    ];
  };
}
