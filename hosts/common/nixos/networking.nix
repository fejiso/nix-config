# Networking configuration
{
  config,
  lib,
  ...
}: {
  # Enable networking
  networking.networkmanager.enable = true;
  
  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [];
    allowedUDPPorts = [];
  };
  
  # Enable IPv6
  networking.enableIPv6 = true;
}
