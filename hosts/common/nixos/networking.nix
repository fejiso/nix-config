# Networking configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable networking
  networking.networkmanager.enable = true;

  # DNS configuration - multiple trusted sources with DNS-over-TLS
  networking.nameservers = [
    # Quad9 (privacy-focused, blocks malware)
    "9.9.9.9"
    "149.112.112.112"
    # Cloudflare (fast, privacy-focused)
    "1.1.1.1"
    "1.0.0.1"
    # Mullvad (privacy-focused)
    "194.242.2.2"
  ];

  # Use systemd-resolved with DNS-over-TLS for encryption
  services.resolved = {
    enable = true;
    dnssec = "allow-downgrade";
    domains = [ "~." ];
    fallbackDns = [
      "9.9.9.9#dns.quad9.net"
      "1.1.1.1#cloudflare-dns.com"
      "194.242.2.2#dns.mullvad.net"
    ];
    dnsovertls = "opportunistic";
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22000 ]; # Syncthing file transfers
    allowedUDPPorts = [ 22000 21027 ]; # Syncthing discovery

    # Allow connections from netbird (wt0 interface)
    interfaces.wt0.allowedTCPPorts = [ 3333 ];
  };

  # Enable IPv6
  networking.enableIPv6 = true;
}
