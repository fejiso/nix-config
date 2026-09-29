{ lib, ... }: {
  options.flake.modules = {
    nixos = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = ''
        NixOS module classes contributed by flake-parts modules. Each name is
        a deferred module that accumulates contributions from every file that
        writes to `flake.modules.nixos.<name>`. Hosts compose by importing
        `config.flake.modules.nixos.default` plus any opt-in features.
      '';
    };

    homeManager = lib.mkOption {
      type = lib.types.lazyAttrsOf lib.types.deferredModule;
      default = { };
      description = "Home-manager module classes, same convention as `nixos`.";
    };
  };

  options.fleet.services = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        host = lib.mkOption {
          type = lib.types.str;
          description = "Host running the service.";
        };
        port = lib.mkOption {
          type = lib.types.port;
          description = "Port the service listens on (on all interfaces / mesh).";
        };
        scheme = lib.mkOption {
          type = lib.types.enum [ "http" "https" ];
          default = "http";
          description = "Upstream scheme the service speaks.";
        };
        public = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Expose through the public ingress as <sub>.<domain> (subdomain map
            lives in secrets/ingress.yaml, rendered to the eval-time-only
            ingress-domains.nix). Non-public services are mesh-only.
          '';
        };
        healthPath = lib.mkOption {
          type = lib.types.str;
          default = "/";
          description = "Path used for health checks.";
        };
        group = lib.mkOption {
          type = lib.types.str;
          default = "Other";
          description = "Grouping label for dashboards/monitors.";
        };
        description = lib.mkOption {
          type = lib.types.str;
          default = "";
        };
        upstream = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "10.2.3.1:80";
          description = ''
            Full "host:port" override for the proxy/health-check target, for
            services that don't run on a nix-config host (LAN appliances,
            foreign machines). When null, the target is derived from
            host/port (loopback for same-host, <host>.netbird.cloud otherwise).
          '';
        };
      };
    });
    default = { };
    description = ''
      Fleet-wide service registry (single source of truth). Consumed by the
      ingress (nginx vhosts) and monitoring (Gatus endpoints) modules, so
      onboarding a service here wires up proxying and monitoring automatically.
    '';
  };
}
