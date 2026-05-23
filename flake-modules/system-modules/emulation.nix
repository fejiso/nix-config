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
    environment.systemPackages = with pkgs; [
      # RetroArch (can serve as frontend)
      retroarch-full
      retroarch-assets
      retroarch-joypad-autoconfig
      librashader
      libretro-shaders-slang

      # DOS
      dosbox-staging
      dosbox-x

      # Retro computers
      x16-emulator

      # Nintendo
      dolphin-emu  # GameCube/Wii

      # Sony
      pcsx2        # PS2
      ppsspp       # PSP
      duckstation  # PS1

      # Arcade
      mame

      # image management
      mame-tools
      _7zz
      unrar
    ];
  };
}
;
}
