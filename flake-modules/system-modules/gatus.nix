{ config, lib, inputs, ... }:
# Gatus monitoring on hierro, generated from the fleet.services registry
# (flake-modules/fleet-services.nix). For each service:
#   - mesh check:  http(s)://<host>.netbird.cloud:<port><healthPath>
#   - public check (public services only): https://<sub>.<domain> — exercises
#     DNS, the router path, ingress TLS and the upstream; also asserts cert
#     expiry > 7d as the safety net for ACME renewal failures.
#   - mesh-mirror check (public services only): https://<sub>.<meshDomain>
#     against hierro's backup ingress (TLS, full path + cert expiry, same
#     rigor as the public check). LAN-upstream services are excluded —
#     hierro can't reach the home LAN, and the mesh flavor doesn't serve them.
#
# Alerting: native Pushover provider, creds interpolated from the
# sops-rendered env file (existing pushover.yaml secrets). The host is baked
# into the endpoint group and alert descriptions at eval time — gatus only
# resolves [ENDPOINT_*] placeholders for the `custom` provider, so with the
# native pushover provider they would be sent literally.
let
  registry = config.fleet.services;
  fleetHosts = config.fleet.hosts;
  fleetRouters = config.fleet.routers;

  loadDomains = import (inputs.private + "/ingress-domains.nix");
in
{
  flake.modules.nixos.gatus = { config, lib, ... }:
    let
      domains = loadDomains;
      sub = name: domains.subdomains.${name} or name;
      publicServices = lib.filterAttrs (_: s: s.public) registry;
      # Mirror the ingress-mesh filter (lan upstreams unreachable from hierro).
      meshMirrorServices = lib.filterAttrs (_: s: s.upstream == null) publicServices;

      mkMesh = name: svc: {
        inherit name;
        group = "${svc.group} (${svc.host})";
        url = "${svc.scheme}://${if svc.upstream != null then svc.upstream else "${svc.host}.netbird.cloud:${toString svc.port}"}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
        ];
        alerts = [{
          type = "pushover";
          description = "${svc.host}: service mesh endpoint unreachable or returned 5xx";
        }];
      };
      mkPublic = name: svc: {
        name = "${name}-public";
        group = "${svc.group} (${svc.host})";
        url = "https://${sub name}.${domains.domain}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
          "[CERTIFICATE_EXPIRATION] > 168h"
        ];
        alerts = [{
          type = "pushover";
          description = "${svc.host}: public ingress unreachable, TLS invalid, or certificate expiring";
        }];
      };
      mkMeshMirror = name: svc: {
        name = "${name}-mesh-ingress";
        group = "${svc.group} (${svc.host})";
        url = "https://${sub name}.${domains.meshDomain}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
          "[CERTIFICATE_EXPIRATION] > 168h"
        ];
        alerts = [{
          type = "pushover";
          description = "${svc.host}: mesh ingress proxy unreachable or returned 5xx";
        }];
      };

      # Fleet-wide TCP probes feeding the blinkenlights matrix rows 0/1.
      # Routers get SSH only (they run netbird per routers/modules/netbird.nix
      # but no microsocks); NixOS hosts get SSH + SOCKS5 (port 1080 is opened
      # on wt0 fleet-wide by flake-modules/system/networking.nix).
      mkSshEndpoint = host: {
        name = "ssh-${host}";
        group = "System (${host})";
        url = "tcp://${host}.netbird.cloud:22";
        interval = "60s";
        conditions = [ "[CONNECTED] == true" ];
        alerts = [{
          type = "pushover";
          description = "${host}: SSH unreachable";
        }];
      };
      mkSocksEndpoint = host: {
        name = "socks-${host}";
        group = "Mesh (${host})";
        url = "tcp://${host}.netbird.cloud:1080";
        interval = "60s";
        conditions = [ "[CONNECTED] == true" ];
        alerts = [{
          type = "pushover";
          description = "${host}: SOCKS5 proxy unreachable";
        }];
      };
    in
    {
      sops.templates."gatus-env" = {
        # gatus runs as a DynamicUser; /run/secrets/rendered is traversable.
        mode = "0444";
        content = ''
          PUSHOVER_APP_TOKEN=${config.sops.placeholder.pushover-app-token}
          PUSHOVER_USER_KEY=${config.sops.placeholder.pushover-user-key}
        '';
      };

      services.gatus = {
        enable = true;
        environmentFile = config.sops.templates."gatus-env".path;
        settings = {
          web.port = 8080;
          # Expose prometheus metrics (scraped by vmagent).
          metrics = true;
          # StateDirectory=gatus -> /var/lib/gatus
          storage = {
            type = "sqlite";
            path = "/var/lib/gatus/data.db";
            caching = true;
          };
          connectivity.checker = {
            target = "1.1.1.1:53";
            interval = "5m";
          };

          alerting.pushover = {
            application-token = "\${PUSHOVER_APP_TOKEN}";
            user-key = "\${PUSHOVER_USER_KEY}";
            default-alert = {
              enabled = true;
              failure-threshold = 3;
              success-threshold = 2;
              send-on-resolved = true;
              description = "healthcheck failed";
            };
          };

          endpoints =
            lib.mapAttrsToList mkMesh registry
            ++ lib.mapAttrsToList mkPublic publicServices
            ++ lib.mapAttrsToList mkMeshMirror meshMirrorServices
            ++ map mkSshEndpoint (fleetHosts ++ fleetRouters)
            ++ map mkSocksEndpoint fleetHosts;
        };
      };

      networking.firewall.interfaces.wt0.allowedTCPPorts = [ 8080 ];
    };
}
