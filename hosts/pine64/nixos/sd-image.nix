{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    (modulesPath + "/installer/sd-card/sd-image-aarch64.nix")
  ];

  # Image configuration
  image.fileName = "nixos-pine64-${config.system.nixos.label}-${pkgs.stdenv.hostPlatform.system}.img.zst";

  # SD image configuration
  sdImage = {
    # Firmware partition size (in MB)
    firmwareSize = 512;

    # Populate firmware with bootloader files
    populateFirmwareCommands = ''
      ${config.system.build.installBootLoader} ${config.system.build.toplevel} -d ./firmware
    '';

    # Populate root with bootloader configuration
    populateRootCommands = ''
      mkdir -p ./files/boot
      ${config.boot.loader.generic-extlinux-compatible.populateCmd} -c ${config.system.build.toplevel} -d ./files/boot
    '';
  };

  # Kernel parameters for first boot
  boot.kernelParams = [
    "console=ttyS0,115200"
    "console=tty1"
  ];
}
