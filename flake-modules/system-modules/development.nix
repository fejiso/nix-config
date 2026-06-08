{ ... }: {
  flake.modules.nixos.development =
{ config, pkgs, lib, ... }:

{
  options = {
    development.enable = lib.mkEnableOption "development tools and embedded programming support";
  };

  config = lib.mkIf config.development.enable {
    # aarch64 builds (rpi3 kernel, SD images) are routed to the native amp1
    # builder. We deliberately do NOT enable qemu binfmt emulation: emulated
    # kernel builds get SIGKILLed, and nix treats that as a machine failure
    # and retries the build across every aarch64-capable builder in a loop.
    # Native amp1 handles aarch64; re-enable emulation only if amp1 is gone.
    # boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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
