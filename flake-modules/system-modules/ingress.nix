{ config, lib, inputs, ... }:
# Declarative nginx ingress, generated from the fleet.services registry
# (flake-modules/fleet-services.nix). Two flavors sharing one builder:
#
#   ingress-public  (butthead): TLS termination for <sub>.<domain> with a
#     Let's Encrypt wildcard cert (ACME DNS-01 via Namecheap), on alternate
#     ports 8003/44303 alongside nginx-proxy-manager until the router
#     port-forwards are flipped manually.
#   ingress-mesh    (hierro): plain HTTP <sub>.<meshDomain> on the netbird
#     mesh only; same subdomain->upstream mappings, proxy (no redirect).
#
# Domains come from the `ingress-secrets` flake input (path:/var/lib/fleet-secrets,
# never committed) — rendered from secrets/ingress.yaml by
# scripts/render-ingress-domains.sh.
let
  registry = config.fleet.services;

  loadDomains = import (inputs.ingress-secrets + "/ingress-domains.nix");

  # Shared nginx config for one ingress instance. A NixOS module.
  mkIngress = { selfHost, domainAttr, tls, httpPort, httpsPort ? 443 }:
    { config, lib, pkgs, hostname, ... }:
    let
      domains = loadDomains;
      domain = domains.${domainAttr};

      publicServices = lib.filterAttrs (_: s: s.public) registry;
      sub = name: domains.subdomains.${name} or name;
      # Local services are proxied via loopback so the ingress survives
      # netbird hiccups; cross-host goes over the mesh; `upstream` overrides
      # both for non-nix-config targets (LAN appliances).
      upstream = svc:
        if svc.upstream != null then svc.upstream
        else if svc.host == selfHost then "127.0.0.1:${toString svc.port}"
        else "${svc.host}.netbird.cloud:${toString svc.port}";
    in
    {
      services.nginx = {
        enable = true;
        recommendedProxySettings = true;
        recommendedOptimisation = true;
        recommendedTlsSettings = tls;
        recommendedBrotliSettings = true;
        recommendedGzipSettings = true;
        additionalModules = [ pkgs.nginxModules.vts ];
        defaultHTTPListenPort = httpPort;

        appendHttpConfig = ''
          vhost_traffic_status_zone;

          # JSON access log to journald; vector picks it up and ships it to
          # VictoriaLogs on hierro (see services.vector below).
          log_format json_ingress escape=json '{"time":"$time_iso8601","remote_addr":"$remote_addr","vhost":"$host","request":"$request","status":$status,"bytes":$body_bytes_sent,"request_time":$request_time,"upstream":"$upstream_addr","upstream_time":"$upstream_response_time","referer":"$http_referer","user_agent":"$http_user_agent"}';
          access_log syslog:server=unix:/dev/log,severity=info json_ingress;
        '';

        # Per-service vhosts from the registry.
        virtualHosts = lib.mapAttrs' (name: svc:
          lib.nameValuePair "${sub name}.${domain}" ({
            locations."/" = {
              proxyPass = "${svc.scheme}://${upstream svc}";
              proxyWebsockets = true;
            };
          } // lib.optionalAttrs tls {
            # Per-vhost HTTP-01 cert (no DNS API available — DNS is managed by
            # the home router). Issues once the router forwards port 80 here;
            # until then the acme module's self-signed fallback keeps nginx
            # running (validate with curl -k --resolve).
            forceSSL = true;
            enableACME = true;
          })
        ) publicServices // {
          # Catch-all: don't serve a random vhost for unknown Host/SNI.
          "_" = {
            default = true;
            rejectSSL = tls;
            locations."/".return = "444";
          };
          # VTS per-vhost traffic stats in prometheus format, mesh-only.
          "vts-status" = {
            listen = [{ addr = "0.0.0.0"; port = 9977; }];
            locations."/status".extraConfig = ''
              vhost_traffic_status_display;
              vhost_traffic_status_display_format prometheus;
            '';
            locations."/".return = "404";
          };
        };
      } // lib.optionalAttrs tls {
        defaultSSLListenPort = httpsPort;
      };

      networking.firewall.interfaces.wt0.allowedTCPPorts = [ 9977 ];

      # Ship the JSON access log to VictoriaLogs on hierro.
      services.vector = {
        enable = true;
        journaldAccess = true;
        settings = {
          sources.nginx = {
            type = "journald";
            include_units = [ "nginx.service" ];
          };
          transforms.nginx_access = {
            type = "remap";
            inputs = [ "nginx" ];
            # Non-JSON lines (error log etc.) fail the parse and are dropped.
            source = ''
              . = parse_json!(.message)
              .log_source = "nginx-access"
              .host = "${hostname}"
            '';
          };
          sinks.victorialogs = {
            type = "http";
            inputs = [ "nginx_access" ];
            uri = "http://hierro.netbird.cloud:9428/insert/jsonline?_stream_fields=host,log_source&_time_field=time";
            encoding.codec = "json";
            framing.method = "newline_delimited";
          };
        };
      };
    };

in
{
  # Public ingress (butthead). Listens on 8003/44303 — nginx-proxy-manager
  # keeps 8002/44302 and stays the live ingress until the router forwards
  # are flipped manually.
  flake.modules.nixos.ingress-public = { config, ... }: {
    imports = [
      (mkIngress {
        selfHost = "butthead";
        domainAttr = "domain";
        tls = true;
        httpPort = 8003;
        httpsPort = 44303;
      })
    ];

    # Let's Encrypt per-vhost certs via HTTP-01. DNS (A records, LAN
    # resolution) is managed by the home router — there is no DNS API, so no
    # wildcard cert. Challenges only reach nginx after the router flip
    # (80 -> 8003); before that nginx serves the acme module's self-signed
    # fallback certs.
    security.acme = {
      acceptTerms = true;
      defaults.email = loadDomains.acmeEmail;
      # Bring-up: staging endpoint to avoid production rate limits while
      # validating. Remove once issuance succeeds post-flip.
      defaults.server = "https://acme-staging-v02.api.letsencrypt.org/directory";
      # All certs feed nginx; renewals reload it without dropping connections.
      defaults.reloadServices = [ "nginx" ];
      defaults.group = "nginx";
    };

    # Ingress ports (LAN/mesh-reachable; router forwards land here only
    # after the manual flip).
    networking.firewall.allowedTCPPorts = [ 8003 44303 ];
  };


  # Mesh-only ingress (hierro): same mappings, plain HTTP, netbird only.
  flake.modules.nixos.ingress-mesh = { ... }: {
    imports = [
      (mkIngress {
        selfHost = "hierro";
        domainAttr = "meshDomain";
        tls = false;
        httpPort = 80;
      })
    ];

    networking.firewall.interfaces.wt0.allowedTCPPorts = [ 80 ];
  };
}
