{ ... }: {
  flake.modules.homeManager.android-tools =
{ config, pkgs, lib, ... }:

with lib;

{
  options.programs.android-tools = {
    enable = mkEnableOption "Android development tools (adb, fastboot)";
  };

  config = mkIf config.programs.android-tools.enable {
    home.packages = with pkgs; [
      android-tools  # Includes adb and fastboot
    ];
  };
}
;
}
