{ ... }: {
  flake.modules.nixos.emulation =
# Emulation module for retro gaming
{ config, lib, pkgs, ... }:

with lib;

{
  options.emulation = {
    enable = mkEnableOption "emulation packages for retro gaming";
  };

  config = mkIf config.emulation.enable {
    environment.systemPackages = [
      # RetroArch (bare + non-MAME cores group-tuned; libretro-mame* kept cached)
      pkgs.groupTune.retroarch-full
      pkgs.retroarch-assets
      pkgs.retroarch-joypad-autoconfig
      pkgs.librashader
      pkgs.libretro-shaders-slang

      # DOS
      pkgs.groupTune.dosbox-staging
      pkgs.groupTune.dosbox-x

      # Retro computers
      pkgs.groupTune.x16-emulator

      # Nintendo
      pkgs.groupTune.dolphin-emu  # GameCube/Wii

      # Sony
      pkgs.groupTune.pcsx2        # PS2
      pkgs.groupTune.ppsspp       # PSP

      # Arcade (kept on cache.nixos.org — ~60m C++ build)
      pkgs.mame

      # image management
      pkgs.mame-tools
      pkgs.groupTune._7zz
      pkgs.unrar
    ];
  };
}
;
}
