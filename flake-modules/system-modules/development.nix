{ ... }: {
  flake.modules.nixos.development =
{ config, pkgs, lib, ... }:

{
  options = {
    development.enable = lib.mkEnableOption "development tools and embedded programming support";
  };

  config = lib.mkIf config.development.enable {
    # Enable QEMU emulation for aarch64 (ARM64) to build SD card images
    boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

    # Install PlatformIO and related tools
    environment.systemPackages = with pkgs; [
      platformio
      avrdude # often helpful to have the system version
      openocd
      uucp # Provides cu for serial communication
      minicom # Alternative serial communication tool
      (vscode.fhsWithPackages (ps: with ps; [
        nix-ld
        platformio
        avrdude
        openocd
        xdg-user-dirs # REQUIRED to prevent the "assert IS_WINDOWS" crash
      ]))
    ];

    # Enable Udev rules for embedded devices
    # This allows your user to access the USB serial ports without sudo
    services.udev.packages = [
      pkgs.platformio-core
      pkgs.openocd
    ];

    # Enable nix-ld (HIGHLY RECOMMENDED)
    # PlatformIO will download compilers (gcc, etc.) that are unpatched binaries.
    # nix-ld allows these unpatched binaries to run on NixOS.
    programs.nix-ld.enable = true;
    programs.nix-ld.libraries = with pkgs; [
      stdenv.cc.cc
      zlib
      ncurses5
      # Add other libs if specific toolchains complain
    ];

    # Add z-247 user to dialout group for serial port access
    users.users.z-247.extraGroups = [ "dialout" ];

    # Enable udisks2 for automatic USB drive mounting
    services.udisks2.enable = true;
  };
}
;
}
