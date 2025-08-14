{ config, pkgs, ... }:

{
  services.kanshi = {
    enable = true;
    profiles = [
      {
        name = "laptop";
        outputs = [
          { name = "LVDS-1"; enable = true; scale = 2; }
        ];
      }
      {
        name = "docked";
        outputs = [
          { name = "LVDS-1"; disable = true; }
          { name = "Some Company ASDF 4242"; mode = "1600x900"; position = "0,0"; }
        ];
      }
      {
        name = "eDP-1_only";
        outputs = [
          { name = "eDP-1"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "eDP-1_and_HDMI-A-1";
        outputs = [
          { name = "eDP-1"; enable = true; position = "0,0"; }
          { name = "HDMI-A-1"; enable = true; position = "1920,0"; }
        ];
      }
      {
        name = "eDP-1_and_DP-1";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "DP-1"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "eDP-1_and_DP-2";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "DP-2"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "eDP-1_and_DP-3";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "DP-3"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "eDP-1_and_DP-4";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "DP-4"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "triple_monitor_1";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "HDMI-A-1"; enable = true; position = "3840,0"; }
          { name = "DP-1"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "triple_monitor_2";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "HDMI-A-1"; enable = true; position = "3840,0"; }
          { name = "DP-2"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "triple_monitor_3";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "HDMI-A-1"; enable = true; position = "3840,0"; }
          { name = "DP-3"; enable = true; position = "0,0"; }
        ];
      }
      {
        name = "triple_monitor_4";
        outputs = [
          { name = "eDP-1"; enable = true; position = "1920,0"; }
          { name = "HDMI-A-1"; enable = true; position = "3840,0"; }
          { name = "DP-4"; enable = true; position = "0,0"; }
        ];
      }
    ];
  };
}