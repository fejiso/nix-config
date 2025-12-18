# Lenovix specific NixOS configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos
    # Add appropriate nixos-hardware module for your specific Lenovo model
    # inputs.nixos-hardware.nixosModules.lenovo-thinkpad-x1-carbon-gen11
  ];

  # Host-specific networking
  networking.hostName = "lenovix";

  # Motion webcam streaming
  services.motion = {
    enable = true;
    settings = {
      daemon = "on";
      webcontrol_localhost = "off";
      webcontrol_port = 8080;
      stream_localhost = "off";
      stream_port = 8081;
      videodevice = "/dev/video0";
      width = 1280;
      height = 720;
      framerate = 15;
      auto_brightness = "on";
      target_dir = "/var/lib/motion";
      text_left = "lenovix";
      text_right = "%Y-%m-%d %H:%M:%S";
    };
  };

  # Open firewall for motion
  networking.firewall.allowedTCPPorts = [ 8080 8081 ];

  # Ensure video group exists and motion user has access
  users.groups.video = {};
  systemd.services.motion.serviceConfig.SupplementaryGroups = [ "video" ];

  # System state version
  system.stateVersion = "25.05";
}
