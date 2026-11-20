{ ... }: {
  flake.modules.nixos.cli =
# Networking configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  failoverCfg = config.networking.wireless.iwd.connectivityFailover;
in {
  options.networking.wireless.iwd.connectivityFailover = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Probe upstream internet connectivity bound to each connected iwd Wi-Fi
        station and automatically rotate to another visible known AutoConnect
        SSID when the current AP has no upstream connectivity.
      '';
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "60s";
      description = "Systemd timer interval between Wi-Fi connectivity checks.";
    };

    failureThreshold = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "Consecutive failed checks on the same SSID before failing over.";
    };

    cooldownSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "Seconds to deprioritize a failed SSID so 3+ networks round-robin instead of ping-ponging.";
    };
  };

  config = {
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

      no_autoconnect = {"InterPooper"}

      psk_networks = data.get("psk", {})
      for ssid, passphrase in psk_networks.items():
          target = f"/var/lib/iwd/{ssid}.psk"
          expected_line = f"Passphrase={passphrase}"
          auto_connect = ssid not in no_autoconnect
          expected_content = f"[Security]\nPassphrase={passphrase}\n"
          if not auto_connect:
              expected_content += "\n[Settings]\nAutoConnect=false\n"

          should_write = True
          if os.path.exists(target):
              try:
                  with open(target, "r") as f:
                      lines = [line.strip() for line in f]
                  if expected_line in lines and (auto_connect or "AutoConnect=false" in lines):
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

  # Rotate iwd Wi-Fi networks when the associated AP loses upstream internet.
  # Probes are bound via SO_BINDTODEVICE (--interface / -I) to each connected
  # iwd station so wired Ethernet or NetBird (wt0) routes never mask a dead AP.
  systemd.services.iwd-connectivity-failover = lib.mkIf (config.networking.wireless.iwd.enable && failoverCfg.enable) {
    description = "Check iwd Wi-Fi upstream connectivity and fail over to another known SSID";
    after = [ "iwd.service" ];
    requires = [ "iwd.service" ];
    path = [ config.systemd.package pkgs.curl pkgs.iputils pkgs.iproute2 ];
    serviceConfig = {
      Type = "oneshot";
      RuntimeDirectory = "iwd-failover";
      RuntimeDirectoryPreserve = "yes";
    };
    script = ''
      exec ${pkgs.python3}/bin/python3 - <<'PY'
      import json
      import os
      import subprocess
      import sys
      import time
      from pathlib import Path

      STATE_FILE = Path("/run/iwd-failover/state.json")
      FAIL_THRESHOLD = ${toString failoverCfg.failureThreshold}
      COOLDOWN_SEC = ${toString failoverCfg.cooldownSeconds}

      def load_state():
          try:
              return json.loads(STATE_FILE.read_text())
          except Exception:
              return {"fails": {}, "dead_until": {}}

      def save_state(st):
          tmp = STATE_FILE.with_suffix(".tmp")
          tmp.write_text(json.dumps(st))
          tmp.replace(STATE_FILE)

      def prop(iface_dict, key, default=None):
          entry = iface_dict.get(key)
          return entry.get("data", default) if isinstance(entry, dict) else default

      def get_managed_objects():
          res = subprocess.run(
              ["busctl", "-j", "call", "net.connman.iwd", "/",
               "org.freedesktop.DBus.ObjectManager", "GetManagedObjects"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
          )
          if res.returncode != 0 or not res.stdout.strip():
              return {}
          payload = json.loads(res.stdout)
          data = payload.get("data") or []
          return data[0] if data and isinstance(data[0], dict) else {}

      def get_ordered_networks(sta_path):
          res = subprocess.run(
              ["busctl", "-j", "call", "net.connman.iwd", sta_path,
               "net.connman.iwd.Station", "GetOrderedNetworks"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
          )
          if res.returncode != 0 or not res.stdout.strip():
              return []
          payload = json.loads(res.stdout)
          data = payload.get("data") or []
          return data[0] if data and isinstance(data[0], list) else []

      def trigger_scan_and_wait(sta_path):
          subprocess.run(
              ["busctl", "call", "net.connman.iwd", sta_path,
               "net.connman.iwd.Station", "Scan"],
              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
          )
          for _ in range(16):
              time.sleep(0.5)
              objs = get_managed_objects()
              sta = objs.get(sta_path, {}).get("net.connman.iwd.Station", {})
              if not prop(sta, "Scanning", False):
                  return objs
          return get_managed_objects()

      def check_interface_internet(ifname):
          # Must have a global IPv4 or IPv6 address assigned first
          addr = subprocess.run(
              ["ip", "-o", "addr", "show", "dev", ifname, "scope", "global"],
              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
          )
          if addr.returncode != 0 or not addr.stdout.strip():
              return False, "no global IP address"

          # Primary check: HTTP 204 over SO_BINDTODEVICE using direct IP --resolve
          # so broken/hijacked DNS does not mask or cause false failures, while
          # captive portals (HTTP 200/302 redirect) are caught immediately.
          saw_captive_redirect = False
          for ip in ("1.1.1.1", "1.0.0.1"):
              res = subprocess.run(
                  ["curl", "--interface", ifname, "--max-time", "5", "-sS",
                   "-o", "/dev/null", "-w", "%{http_code}",
                   "--resolve", f"cp.cloudflare.com:80:{ip}",
                   "http://cp.cloudflare.com/generate_204"],
                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True,
              )
              code = res.stdout.strip()
              if res.returncode == 0 and code == "204":
                  return True, f"HTTP 204 via {ip}"
              if res.returncode == 0 and code and code != "000":
                  saw_captive_redirect = True

          if saw_captive_redirect:
              return False, "captive portal / non-204 HTTP intercept"

          # Fallback: raw ICMP in case port 80 is filtered upstream
          for target in ("9.9.9.9", "1.1.1.1"):
              ping = subprocess.run(
                  ["ping", "-I", ifname, "-c", "1", "-W", "3", target],
                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
              )
              if ping.returncode == 0:
                  return True, f"ICMP {target}"

          return False, "HTTP 204 and ICMP probes timed out"

      objs = get_managed_objects()
      if not objs:
          sys.exit(0)

      state = load_state()
      now = time.time()
      state["dead_until"] = {
          k: v for k, v in state.get("dead_until", {}).items() if v > now
      }
      fails = state.setdefault("fails", {})
      changed = False

      for sta_path, ifaces in list(objs.items()):
          sta = ifaces.get("net.connman.iwd.Station")
          dev = ifaces.get("net.connman.iwd.Device")
          if not sta or not dev or not prop(dev, "Powered", False):
              continue

          ifname = prop(dev, "Name")
          sta_state = prop(sta, "State")
          conn_net_path = prop(sta, "ConnectedNetwork")
          if not ifname or sta_state != "connected" or not conn_net_path:
              if ifname in fails:
                  fails.pop(ifname, None)
                  changed = True
              continue

          cur_net = objs.get(conn_net_path, {}).get("net.connman.iwd.Network", {})
          cur_ssid = prop(cur_net, "Name", "")
          if not cur_ssid:
              continue

          ok, detail = check_interface_internet(ifname)
          if ok:
              if ifname in fails or cur_ssid in state["dead_until"]:
                  print(f"{ifname} ('{cur_ssid}'): connectivity restored ({detail})")
                  fails.pop(ifname, None)
                  state["dead_until"].pop(cur_ssid, None)
                  changed = True
              continue

          rec = fails.get(ifname)
          count = (rec.get("count", 0) + 1) if (isinstance(rec, dict) and rec.get("ssid") == cur_ssid) else 1
          fails[ifname] = {"ssid": cur_ssid, "count": count}
          changed = True
          print(f"{ifname} ('{cur_ssid}'): connectivity failed ({count}/{FAIL_THRESHOLD}: {detail})")

          if count < FAIL_THRESHOLD:
              continue

          state["dead_until"][cur_ssid] = now + COOLDOWN_SEC
          fails[ifname] = {"ssid": cur_ssid, "count": 0}

          objs = trigger_scan_and_wait(sta_path)
          ordered = get_ordered_networks(sta_path)

          candidates = []
          for item in ordered:
              if not isinstance(item, list) or len(item) < 2:
                  continue
              net_path, rssi_centi = item[0], item[1]
              net_iface = objs.get(net_path, {}).get("net.connman.iwd.Network", {})
              ssid = prop(net_iface, "Name", "")
              known_path = prop(net_iface, "KnownNetwork")
              if not ssid or ssid == cur_ssid or not known_path:
                  continue
              known_iface = objs.get(known_path, {}).get("net.connman.iwd.KnownNetwork", {})
              if not prop(known_iface, "AutoConnect", True):
                  continue
              dead_ts = state["dead_until"].get(ssid, 0.0)
              candidates.append((dead_ts > now, dead_ts, -int(rssi_centi), ssid, net_path, int(rssi_centi)))

          if not candidates:
              print(f"{ifname} ('{cur_ssid}'): no alternative known AutoConnect SSIDs in range; staying connected")
              continue

          # Prefer non-cooldown networks ordered by strongest RSSI; if all visible
          # alternatives are on cooldown, pick the least-recently-failed one.
          candidates.sort(key=lambda c: (1 if c[0] else 0, c[1] if c[0] else 0.0, c[2]))
          _in_cd, _dts, _neg_rssi, next_ssid, next_path, rssi_centi = candidates[0]
          print(f"{ifname}: rotating from dead SSID '{cur_ssid}' -> '{next_ssid}' ({rssi_centi / 100.0:.1f} dBm)")
          save_state(state)
          changed = False
          subprocess.run(
              ["busctl", "--timeout=25s", "call", "net.connman.iwd", next_path,
               "net.connman.iwd.Network", "Connect"],
              check=False,
          )

      if changed:
          save_state(state)
      PY
    '';
  };

  systemd.timers.iwd-connectivity-failover = lib.mkIf (config.networking.wireless.iwd.enable && failoverCfg.enable) {
    description = "Periodically check iwd Wi-Fi connectivity and rotate dead SSIDs";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "90s";
      OnUnitActiveSec = failoverCfg.interval;
      AccuracySec = "10s";
    };
  };

  # Enable IPv6
  networking.enableIPv6 = true;
  };
}
;
}
