{ ... }: {
  flake.modules.nixos.cli =
# Networking configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Enable NetworkManager for wired, VPN, NetBird, and virtual interfaces
  networking.networkmanager.enable = true;
  # Tell NetworkManager to ignore Wi-Fi interfaces so iwd manages them standalone
  networking.networkmanager.unmanaged = [ "type:wifi" ];
  networking.wireless.enable = lib.mkForce false;

  # Configure iwd standalone for wireless
  networking.wireless.iwd = {
    enable = true;
    settings = {
      General = {
        EnableNetworkConfiguration = true;
        NameResolvingService = "systemd";
      };
      Network = {
        EnableIPv6 = true;
        RoutePriorityOffset = 300;
      };
    };
  };

  # Wireless tools for interactive and scriptable network management
  environment.systemPackages = with pkgs; [
    impala
    iwmenu
  ];

  # Sync sops-managed Wi-Fi network configurations to /var/lib/iwd
  systemd.services.iwd-secrets-sync = lib.mkIf (config.networking.wireless.iwd.enable && (config.sops.secrets ? wifi-secrets)) {
    description = "Sync sops-managed Wi-Fi network configurations to /var/lib/iwd";
    wantedBy = [ "iwd.service" ];
    before = [ "iwd.service" ];
    after = [ "sops-nix.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.python3}/bin/python3 - <<'EOF'
      import json, os, subprocess

      secret_path = "${config.sops.secrets.wifi-secrets.path}"
      if not os.path.exists(secret_path):
          print(f"Secret file {secret_path} not found, skipping sync.")
          exit(0)

      try:
          raw = subprocess.check_output(["${pkgs.yq-go}/bin/yq", "eval", "-o=json", secret_path])
          data = json.loads(raw)
      except Exception as e:
          print(f"Error parsing wifi secrets: {e}")
          exit(1)

      os.makedirs("/var/lib/iwd", mode=0o700, exist_ok=True)

      psk_networks = data.get("psk", {})
      for ssid, passphrase in psk_networks.items():
          target = f"/var/lib/iwd/{ssid}.psk"
          expected_line = f"Passphrase={passphrase}"
          expected_content = f"[Security]\nPassphrase={passphrase}\n"

          should_write = True
          if os.path.exists(target):
              try:
                  with open(target, "r") as f:
                      lines = [line.strip() for line in f]
                  if expected_line in lines:
                      should_write = False
              except Exception:
                  should_write = True

          if should_write:
              print(f"Writing iwd profile for {ssid}")
              tmp = f"{target}.tmp"
              with open(tmp, "w") as f:
                  f.write(expected_content)
              os.chmod(tmp, 0o600)
              os.replace(tmp, target)

      open_networks = data.get("open", [])
      for ssid in open_networks:
          target = f"/var/lib/iwd/{ssid}.open"
          if not os.path.exists(target):
              print(f"Writing open iwd profile for {ssid}")
              tmp = f"{target}.tmp"
              with open(tmp, "w") as f:
                  f.write("[Settings]\nAutoConnect=true\n")
              os.chmod(tmp, 0o600)
              os.replace(tmp, target)
      EOF
    '';
  };

  # DNS configuration - DNS-over-TLS via systemd-resolved.
  # Mullvad belongs only in fallbackDns below: its public DNS refuses plain
  # UDP/53 and requires SNI dns.mullvad.net, which the #hostname suffix supplies.
  networking.nameservers = [
    # Quad9 (privacy-focused, blocks malware)
    "9.9.9.9"
    "149.112.112.112"
    # Cloudflare (fast, privacy-focused)
    "1.1.1.1"
    "1.0.0.1"
  ];

  # Use systemd-resolved with DNS-over-TLS for encryption
  services.resolved = {
    enable = true;
    settings.Resolve = {
      DNSSEC = "no";
      Domains = [ "~." ];
      FallbackDNS = [
        "9.9.9.9#dns.quad9.net"
        "1.1.1.1#cloudflare-dns.com"
        "194.242.2.2#dns.mullvad.net"
      ];
      DNSOverTLS = "opportunistic";
    };
  };

  # Firewall
  networking.firewall = {
    enable = true;
    allowedTCPPorts = [ 22000 ]; # Syncthing file transfers
    allowedUDPPorts = [ 22000 21027 ]; # Syncthing discovery

    # Allow connections from netbird (wt0 interface)
    interfaces.wt0.allowedTCPPorts = [ 3333 1080 ];
  };

  # Enable IPv6
  networking.enableIPv6 = true;
}
;
}
