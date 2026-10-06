{ config, lib, inputs, ... }:
# Gatus monitoring on hierro, generated from the fleet.services registry
# (flake-modules/fleet-services.nix). For each service:
#   - mesh check:  http(s)://<host>.netbird.cloud:<port><healthPath>
#   - public check (public services only): https://<sub>.<domain> — exercises
#     DNS, the router path, ingress TLS and the upstream; also asserts cert
#     expiry > 7d as the safety net for ACME renewal failures.
#   - mesh-mirror check (public services only): http://<sub>.<meshDomain>
#     against hierro's own nginx mesh ingress.
#
# Alerting: Pushover via gatus' custom provider, creds interpolated from the
# sops-rendered env file (existing pushover.yaml secrets).
let
  registry = config.fleet.services;

  loadDomains = import (inputs.ingress-secrets + "/ingress-domains.nix");
in
{
  flake.modules.nixos.gatus = { config, lib, ... }:
    let
      domains = loadDomains;
      sub = name: domains.subdomains.${name} or name;
      publicServices = lib.filterAttrs (_: s: s.public) registry;

      mkMesh = name: svc: {
        inherit name;
        inherit (svc) group;
        url = "${svc.scheme}://${if svc.upstream != null then svc.upstream else "${svc.host}.netbird.cloud:${toString svc.port}"}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
        ];
        alerts = [{
          type = "pushover";
          description = "Service mesh endpoint unreachable or returned 5xx";
        }];
      };
      mkPublic = name: svc: {
        name = "${name}-public";
        inherit (svc) group;
        url = "https://${sub name}.${domains.domain}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
          "[CERTIFICATE_EXPIRATION] > 168h"
        ];
        alerts = [{
          type = "pushover";
          description = "Public ingress unreachable, TLS invalid, or certificate expiring";
        }];
      };
      mkMeshMirror = name: svc: {
        name = "${name}-mesh-ingress";
        inherit (svc) group;
        url = "http://${sub name}.${domains.meshDomain}${svc.healthPath}";
        interval = "60s";
        conditions = [
          "[STATUS] >= 200"
          "[STATUS] < 500"
        ];
        alerts = [{
          type = "pushover";
          description = "Mesh ingress proxy unreachable or returned 5xx";
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
            ++ lib.mapAttrsToList mkMeshMirror publicServices;
        };
      };

      networking.firewall.interfaces.wt0.allowedTCPPorts = [ 8080 ];
    };
}
