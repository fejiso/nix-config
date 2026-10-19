{ config, lib, inputs, ... }:
# Authelia SSO portal on butthead, protecting the ingress vhosts via nginx
# forward-auth (auth_request — see flake-modules/system-modules/ingress.nix,
# which reads the per-service `sso` flag from this registry).
#
# Runs co-located with the public ingress; the mesh ingress on hierro reaches
# the authz endpoint over netbird (port 9091 is opened on wt0 only).
#
# Secrets (secrets/authelia.yaml in the nix-config-private repo — generate
# with scripts/setup-authelia-secrets.sh there):
#   jwt_secret, session_secret, storage_encryption_key: random 64-hex strings
#   users_database: file-based user DB (argon2id hashes), the whole file as
#     one YAML string key; adding a friend = edit + redeploy.
#
# The portal vhost is the registry entry `auth` below (auth.<domain> and
# auth.<meshDomain>); the entry sets sso = false to avoid the chicken-and-egg.
#
# Mesh SSO runs over TLS: auth.<meshDomain> is served by hierro's backup
# ingress (ingress-mesh, per-vhost LE certs), so the https authelia_url
# satisfies Authelia's validation and Secure cookies work.
let
  loadDomains = import (inputs.private + "/ingress-domains.nix");
in
{
  # Registry entry: generates the auth.<domain> / auth.<meshDomain> vhosts.
  fleet.services.auth = {
    host = "butthead";
    port = 9091;
    public = true;
    sso = false; # the portal can't require its own auth
    group = "Infra";
    description = "SSO portal (Authelia)";
    healthPath = "/api/health";
  };

  flake.modules.nixos.authelia = { config, ... }:
    let
      domains = loadDomains;
    in
    {
      sops.secrets = {
        authelia-jwt-secret = {
          sopsFile = "${inputs.private}/secrets/authelia.yaml";
          key = "jwt_secret";
        };
        authelia-session-secret = {
          sopsFile = "${inputs.private}/secrets/authelia.yaml";
          key = "session_secret";
        };
        authelia-storage-key = {
          sopsFile = "${inputs.private}/secrets/authelia.yaml";
          key = "storage_encryption_key";
        };
        authelia-users-db = {
          sopsFile = "${inputs.private}/secrets/authelia.yaml";
          key = "users_database";
        };
      };

      # The authelia unit runs with PrivateUsers=true, so its uid can't read
      # root-owned files in /run/secrets. Copy the secrets through templates:
      # /run/secrets/rendered is world-traversable (same pattern as gatus).
      sops.templates = {
        "authelia-jwt-secret" = {
          mode = "0444";
          content = config.sops.placeholder.authelia-jwt-secret;
        };
        "authelia-session-secret" = {
          mode = "0444";
          content = config.sops.placeholder.authelia-session-secret;
        };
        "authelia-storage-key" = {
          mode = "0444";
          content = config.sops.placeholder.authelia-storage-key;
        };
        "authelia-users-db" = {
          mode = "0444";
          content = config.sops.placeholder.authelia-users-db;
        };
      };

      # Session storage (Authelia requires Redis).
      services.redis.servers.authelia = {
        enable = true;
        bind = "127.0.0.1";
        port = 6380;
      };

      services.authelia.instances.main = {
        enable = true;
        secrets = {
          jwtSecretFile = config.sops.templates."authelia-jwt-secret".path;
          sessionSecretFile = config.sops.templates."authelia-session-secret".path;
          storageEncryptionKeyFile = config.sops.templates."authelia-storage-key".path;
        };
        settings = {
          theme = "dark";
          log.level = "info";

          # Loopback for the local public ingress + wt0 for hierro's mesh
          # ingress; the firewall below restricts 9091 to wt0.
          server.address = "tcp://0.0.0.0:9091";

          authentication_backend = {
            # Users are managed declaratively in sops; no SMTP notifier, so
            # self-service password flows can't work anyway.
            password_change.disable = true;
            password_reset.disable = true;
            file.path = config.sops.templates."authelia-users-db".path;
          };

          access_control = {
            default_policy = "deny";
            rules = [
              {
                domain = [ "*.${domains.domain}" "*.${domains.meshDomain}" ];
                policy = "two_factor";
              }
            ];
          };

          session = {
            cookies = [
              {
                domain = domains.domain;
                authelia_url = "https://auth.${domains.domain}";
              }
              {
                domain = domains.meshDomain;
                authelia_url = "https://auth.${domains.meshDomain}";
              }
            ];
            redis = {
              host = "127.0.0.1";
              port = 6380;
            };
          };

          regulation = {
            max_retries = 5;
            find_time = "2m";
            ban_time = "10m";
          };

          # StateDirectory=authelia-main (set by the nixpkgs module).
          storage.local.path = "/var/lib/authelia-main/db.sqlite3";
          notifier.filesystem.filename = "/var/lib/authelia-main/notifications.txt";
        };
      };

      systemd.services.authelia-main = {
        after = [ "redis-authelia.service" ];
        requires = [ "redis-authelia.service" ];
      };

      # Mesh-only: hierro's nginx auth_request + browsers hitting
      # auth.<meshDomain>. Not opened on the public/LAN interfaces.
      networking.firewall.interfaces.wt0.allowedTCPPorts = [ 9091 ];
    };
}
