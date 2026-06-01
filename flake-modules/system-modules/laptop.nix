{ ... }: {
  flake.modules.nixos.laptop =
# Laptop-specific configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  # Laptop-specific power management
  services.logind.settings.Login = {
    HandleLidSwitch = "suspend";
    HandleLidSwitchExternalPower = "ignore";
    HandleLidSwitchDocked = "ignore";
  };

  # Screen timeout and DPMS
  services.xserver.displayManager.sessionCommands = lib.mkIf config.services.xserver.enable ''
    ${pkgs.xorg.xset}/bin/xset dpms 300 600 900
    ${pkgs.xorg.xset}/bin/xset s 300 300
  '';

  # Console blanking (for kmscon/tty)
  boot.kernelParams = [ "consoleblank=300" ];

  # Battery management and power saving
  services.upower.enable = true;
  services.thermald.enable = true;
  
  # Disable GNOME's power-profiles-daemon to avoid conflicts with TLP
  services.power-profiles-daemon.enable = false;
  
  # Laptop-specific services
  services.tlp = {
    enable = true;
    settings = {
      TLP_DEFAULT_MODE = "AC";
      TLP_PERSISTENT_DEFAULT = 0;
      
      # CPU scaling
      CPU_SCALING_GOVERNOR_ON_AC = "performance";
      CPU_SCALING_GOVERNOR_ON_BAT = "powersave";
      
      # Energy performance hints
      CPU_ENERGY_PERF_POLICY_ON_AC = "performance";
      CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
      
      # WiFi power saving
      WIFI_PWR_ON_AC = "off";
      WIFI_PWR_ON_BAT = "on";
      
      # USB autosuspend
      USB_AUTOSUSPEND = 1;
      USB_BLACKLIST_PHONE = 1;
    };
  };
  
  # Enable touchpad support
  services.libinput = {
    enable = true;
    touchpad = {
      tapping = true;
      naturalScrolling = true;
      middleEmulation = true;
    };
  };
  
  # Bluetooth for laptops
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };
  services.blueman.enable = true;

  # Laptop-specific packages
  environment.systemPackages = with pkgs; [
    powertop
    brightnessctl
  ];
};
}
