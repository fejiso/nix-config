{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Disable x86-specific graphics for ARM
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # Image configuration
  image.baseName = "nixos-rpi3-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}";

  # SD image configuration
  sdImage = {
    # Firmware partition size (in MB)
    firmwareSize = 512;

    # Populate firmware with bootloader files
    populateFirmwareCommands = ''
      ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
    '';

    # UUID for root partition
    rootPartitionUUID = lib.mkForce "14e19a7b-0ae0-484d-9d54-43bd6fdc20c7";
  };

  # Kernel parameters for first boot
  boot.kernelParams = [
    "console=ttyAMA0,115200"
    "console=tty1"
  ];
}
