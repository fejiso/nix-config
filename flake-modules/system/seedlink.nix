{ ... }: {
  flake.modules.nixos.default =
# SeedLink relay — socat proxies on ports 18000–18006 (netbird/wt0 only)
# Each local port forwards to a different upstream seismological data server
{ lib, pkgs, ... }:

let
  seedlinkUpstreams = [
    { port = 18000; host = "rtserve.iris.washington.edu:18000"; name = "iris"; }
    { port = 18001; host = "geofon.gfz-potsdam.de:18000";      name = "geofon"; }
    { port = 18002; host = "rtserve.resif.fr:18000";            name = "resif"; }
    { port = 18003; host = "eida.bgr.de:18000";                 name = "bgr"; }
    { port = 18004; host = "link.geonet.org.nz:18000";          name = "geonet"; }
    { port = 18005; host = "rtserver.ipgp.fr:18000";            name = "ipgp"; }
    { port = 18006; host = "eida.orfeus-eu.org:18000";          name = "orfeus"; }
  ];
  mkRelay = s: {
    name = "seedlink-relay-${s.name}";
    value = {
      description = "SeedLink relay ${s.name} (wt0:${toString s.port} -> ${s.host})";
      after = [ "network-online.target" "sys-subsystem-net-devices-wt0.device" ];
      wants = [ "network-online.target" ];
      bindsTo = [ "sys-subsystem-net-devices-wt0.device" ];
      wantedBy = [ "multi-user.target" ];
      path = [ pkgs.iproute2 pkgs.gawk ];
      script = ''
        IP=$(ip -4 addr show wt0 | awk '/inet / {print $2}' | cut -d/ -f1 | head -1)
        if [ -n "$IP" ]; then
          exec ${pkgs.socat}/bin/socat TCP-LISTEN:${toString s.port},bind="$IP",fork,reuseaddr TCP:${s.host}
        else
          echo "Could not get IP for wt0 interface"
          exit 1
        fi
      '';
      serviceConfig = {
        Restart = "always";
        RestartSec = "10";
        DynamicUser = true;
      };
    };
  };
in {
  systemd.services = builtins.listToAttrs (map mkRelay seedlinkUpstreams);

  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 18000 18001 18002 18003 18004 18005 18006 ];
}
;
}
