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

  # Webcam streaming with mjpg-streamer
  systemd.services.mjpg-streamer = {
    description = "MJPG Streamer for webcam";
    after = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "mjpg-streamer";
      Group = "video";
      Restart = "always";
      RestartSec = "5s";

      ExecStart = ''
        ${pkgs.mjpg-streamer}/bin/mjpg_streamer \
          -i "input_uvc.so -d /dev/video0 -r 1280x720 -f 15" \
          -o "output_http.so -p 8080 -w ${pkgs.mjpg-streamer}/share/mjpg-streamer/www"
      '';
    };
  };

  # Create mjpg-streamer user
  users.users.mjpg-streamer = {
    isSystemUser = true;
    group = "video";
  };
  users.groups.video = {};

  # Open firewall for webcam stream
  networking.firewall.allowedTCPPorts = [ 8080 ];

  # System state version
  system.stateVersion = "25.05";
}
