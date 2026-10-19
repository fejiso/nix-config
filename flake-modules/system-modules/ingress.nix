{ config, lib, inputs, ... }:
# Declarative nginx ingress, generated from the fleet.services registry
# (flake-modules/fleet-services.nix). Two flavors sharing one builder:
#
#   ingress-public  (butthead): TLS termination for <sub>.<domain> with a
#     Let's Encrypt wildcard cert (ACME DNS-01 via Namecheap), on alternate
#     ports 8003/44303 alongside nginx-proxy-manager until the router
#     port-forwards are flipped manually.
#   ingress-mesh    (hierro): public BACKUP ingress for <sub>.<meshDomain> —
#     TLS-terminated on hierro's public IPs (per-vhost ACME HTTP-01, hierro
#     owns the IP so no router flip needed), proxying to backends over the
#     mesh. Same subdomain->upstream mappings as the public flavor.
#
# Domains come from the `private` flake input (nix-config-private repo,
# <input>/ingress-domains.nix — hand-edited, never committed here).
let
  registry = config.fleet.services;

  loadDomains = import (inputs.private + "/ingress-domains.nix");

  # Shared nginx config for one ingress instance. A NixOS module.
  # includeService: extra predicate on top of `public` (the mesh flavor uses
  # it to drop lan-upstream services it can't reach).
  mkIngress = { selfHost, domainAttr, tls, httpPort, httpsPort ? 443, includeService ? (_: true) }:
    { config, lib, pkgs, hostname, ... }:
    let
      domains = loadDomains;
      domain = domains.${domainAttr};

      publicServices = lib.filterAttrs (_: s: s.public && includeService s) registry;
      sub = name: domains.subdomains.${name} or name;
      # Local services are proxied via loopback so the ingress survives
      # netbird hiccups; cross-host goes over the mesh; `upstream` overrides
      # both for non-nix-config targets (LAN appliances).
      upstream = svc:
        if svc.upstream != null then svc.upstream
        else if svc.host == selfHost then "127.0.0.1:${toString svc.port}"
        else "${svc.host}.netbird.cloud:${toString svc.port}";
      # Authelia forward-auth endpoint (auth_request). butthead's public
      # ingress hits it on loopback; hierro's mesh ingress crosses the mesh.
      autheliaAuthz =
        if selfHost == "butthead" then "127.0.0.1:9091"
        else "butthead.netbird.cloud:9091";
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

        # Per-service vhosts from the registry. Services with `sso = true`
        # (the default) sit behind Authelia forward-auth: nginx asks the
        # authz endpoint per request and bounces unauthenticated browsers to
        # the auth portal (Location header it returns carries the right
        # per-domain portal + rd redirect). Identity is passed upstream as
        # Remote-* headers for apps that support them.
        virtualHosts = lib.mapAttrs' (name: svc:
          lib.nameValuePair "${sub name}.${domain}" ({
            locations = {
              "/" = {
                proxyPass = "${svc.scheme}://${upstream svc}";
                proxyWebsockets = true;
                extraConfig = lib.optionalString svc.sso ''
                  auth_request /authelia;
                  auth_request_set $redirection_url $upstream_http_location;
                  auth_request_set $user $upstream_http_remote_user;
                  auth_request_set $groups $upstream_http_remote_groups;
                  auth_request_set $name $upstream_http_remote_name;
                  auth_request_set $email $upstream_http_remote_email;
                  proxy_set_header Remote-User $user;
                  proxy_set_header Remote-Groups $groups;
                  proxy_set_header Remote-Name $name;
                  proxy_set_header Remote-Email $email;
                  error_page 401 =302 $redirection_url;
                '';
              };
            } // lib.optionalAttrs svc.sso {
              # Authelia authz endpoint (4.38+ auth-request variant).
              "= /authelia" = {
                proxyPass = "http://${autheliaAuthz}/api/authz/auth-request";
                extraConfig = ''
                  internal;
                  proxy_set_header Host $host;
                  proxy_set_header X-Original-Method $request_method;
                  proxy_set_header X-Original-URL $scheme://$http_host$request_uri;
                  proxy_set_header X-Forwarded-For $remote_addr;
                  proxy_set_header Content-Length "";
                  proxy_pass_request_body off;
                '';
              };
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
          "_" = ({
            default = true;
            rejectSSL = tls;
            locations."/".return = "444";
          });
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


  # Backup ingress (hierro): same mappings, TLS-terminated on hierro's
  # public IPs. *.<meshDomain> has a wildcard record -> hierro, so this
  # is the working path when the home line (butthead ingress) is down.
  # LAN-upstream services (router/router3) are excluded — hierro can't reach
  # the home LAN. Vhosts listen on the wildcard address: n8n.nix also listens
  # on the wildcard, so server_name routing decides (explicit-address binds
  # would create separate sockets and shadow each other).
  flake.modules.nixos.ingress-mesh = { ... }: {
    imports = [
      (mkIngress {
        selfHost = "hierro";
        domainAttr = "meshDomain";
        tls = true;
        httpPort = 80;
        includeService = svc: svc.upstream == null;
      })
    ];

    # Production Let's Encrypt, per-vhost HTTP-01 (hierro owns the public IP;
    # the staging endpoint is only in butthead's ingress-public bring-up).
    # Owns ACME on hierro — n8n's vhost certs use these defaults too.
    security.acme = {
      acceptTerms = true;
      defaults.email = loadDomains.acmeEmail;
      defaults.reloadServices = [ "nginx" ];
      defaults.group = "nginx";
    };

    networking.firewall.interfaces.wt0.allowedTCPPorts = [ 80 443 ];
  };
}
