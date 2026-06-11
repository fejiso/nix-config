{ ... }: {
  flake.modules.nixos.quadlet-containers =
# Quadlet containers module - rootless podman via home-manager
# This module sets up home-manager configurations for podman users
# and defines their containers using quadlet-nix
{
  config,
  lib,
  pkgs,
  inputs,
  quadlet-nix,
  ...
}:

with lib;

let
  # Common container config for media services
  mediaContainerDefaults = {
    userns = "keep-id:uid=13106,gid=13100";
    environments = {
      PUID = "13106";
      PGID = "13100";
      UMASK = "002";
      TZ = "Europe/Dublin";
    };
    autoUpdate = "registry";
    logDriver = "journald";
  };

  # Helper to merge container configs
  mkMediaContainer = { image, port, volumes, extraEnv ? {}, extraConfig ? {} }:
    recursiveUpdate {
      autoStart = true;
      containerConfig = recursiveUpdate mediaContainerDefaults {
        inherit image volumes;
        publishPorts = [ "${toString port}:${toString port}" ];
        environments = mediaContainerDefaults.environments // extraEnv;
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "900";  # 15 minutes
      };
    } extraConfig;

in {
  options.services.quadlet-media = {
    enable = mkEnableOption "Quadlet-based media containers";
  };

  options.services.quadlet-utils = {
    enable = mkEnableOption "Quadlet-based utility containers";
  };

  config = mkMerge [
    # Media services containers (run as media-podman user)
    (mkIf config.services.quadlet-media.enable {
      # Home-manager configuration for media-podman user
      home-manager.users.media-podman = { pkgs, ... }: {
        imports = [ quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = "25.05";
        home.enableNixpkgsReleaseCheck = false;
        home.homeDirectory = "/var/lib/media-podman";
        home.username = "media-podman";

        # Quadlet container definitions
        virtualisation.quadlet.containers = {
          # Sonarr - TV Series Manager
          sonarr = mkMediaContainer {
            image = "lscr.io/linuxserver/sonarr:latest";
            port = 8989;
            volumes = [
              "/var/lib/sonarr:/config:rw"
              "/mnt/user/download:/downloads:rw"
              "/mnt/user/Series:/tv:rw"
            ];
          };

          # Radarr - Movie Manager
          radarr = mkMediaContainer {
            image = "lscr.io/linuxserver/radarr:latest";
            port = 7878;
            volumes = [
              "/var/lib/radarr:/config:rw"
              "/mnt/user/download:/downloads:rw"
              "/mnt/user/Movies:/movies:rw"
            ];
          };

          # Lidarr - Music Manager
          lidarr = mkMediaContainer {
            image = "lscr.io/linuxserver/lidarr:latest";
            port = 8686;
            volumes = [
              "/var/lib/lidarr:/config:rw"
              "/mnt/user/download:/downloads:rw"
              "/mnt/user/Music:/music:rw"
            ];
          };

          # Prowlarr - Indexer Manager
          prowlarr = mkMediaContainer {
            image = "lscr.io/linuxserver/prowlarr:latest";
            port = 9696;
            volumes = [
              "/var/lib/prowlarr:/config:rw"
            ];
          };

          # LazyLibrarian - Book Manager
          lazylibrarian = mkMediaContainer {
            image = "lscr.io/linuxserver/lazylibrarian:latest";
            port = 5299;
            volumes = [
              "/var/lib/lazylibrarian:/config:rw"
              "/mnt/user/Books:/books:rw"
              "/mnt/user/download:/downloads:rw"
            ];
          };

          # SABnzbd - Usenet Downloader
          sabnzbd = mkMediaContainer {
            image = "lscr.io/linuxserver/sabnzbd:latest";
            port = 8080;
            volumes = [
              "/var/lib/sabnzbd:/config:rw"
              "/mnt/user/download:/downloads:rw"
              "/mnt/user/downloadtemp/incomplete:/incomplete-downloads:rw"
            ];
          };

          # Deluge - BitTorrent Client
          deluge = mkMediaContainer {
            image = "lscr.io/linuxserver/deluge:latest";
            port = 8112;
            volumes = [
              "/var/lib/deluge:/config:rw"
              "/mnt/user/download:/downloads:rw"
            ];
          };

          # Emby Media Server
          emby = {
            autoStart = true;
            containerConfig = {
              image = "lscr.io/linuxserver/emby:latest";
              publishPorts = [ "8096:8096" ];
              volumes = [
                "/var/lib/emby:/config:rw"
                "/mnt/user/Movies:/movies:ro"
                "/mnt/user/Series:/tv:ro"
                "/mnt/user/Music:/music:ro"
                "/mnt/user/Backups/Emby:/backup:rw"
              ];
              tmpfses = [ "/run" "/var/run" ];
              environments = {
                PUID = "0";
                PGID = "0";
                UMASK = "002";
                TZ = "Europe/Dublin";
              };
              autoUpdate = "registry";
              devices = [ "/dev/dri:/dev/dri" ];
              shmSize = "1024m";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Gluetun VPN Client
          gluetun = {
            autoStart = true;
            containerConfig = {
              image = "ghcr.io/qdm12/gluetun:latest";
              publishPorts = [ "8084:8080" ];
              volumes = [
                "/var/lib/gluetun:/gluetun:rw"
              ];
              environments = {
                VPN_SERVICE_PROVIDER = "nordvpn";
                VPN_TYPE = "openvpn";
                SERVER_COUNTRIES = "Ireland";
                FIREWALL_VPN_INPUT_PORTS = "8080";
                TZ = "Europe/Dublin";
                UPDATER_PERIOD = "24h";
              };
              environmentFiles = [ "/run/secrets/nordvpn-credentials-env" ];
              addCapabilities = [ "NET_ADMIN" ];
              devices = [ "/dev/net/tun:/dev/net/tun" ];
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # qBittorrent via Gluetun VPN
          qbittorrent = {
            autoStart = true;
            containerConfig = {
              image = "lscr.io/linuxserver/qbittorrent:latest";
              userns = "keep-id:uid=13106,gid=13100";
              networks = [ "container:gluetun" ];
              volumes = [
                "/var/lib/qbittorrent:/config:rw"
                "/mnt/user/download:/downloads:rw"
              ];
              environments = {
                PUID = "13106";
                PGID = "13100";
                UMASK = "002";
                TZ = "Europe/Dublin";
                WEBUI_PORT = "8080";
              };
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
            unitConfig = {
              After = [ "gluetun.service" ];
              Requires = [ "gluetun.service" ];
            };
          };
        };
      };

      # System-level setup for media-podman user
      systemd.tmpfiles.rules = [
        "d /run/user/13106 0700 media-podman media-services -"
        "d /var/lib/sonarr 0755 media-podman media-services -"
        "d /var/lib/radarr 0755 media-podman media-services -"
        "d /var/lib/lidarr 0755 media-podman media-services -"
        "d /var/lib/prowlarr 0755 media-podman media-services -"
        "d /var/lib/lazylibrarian 0755 media-podman media-services -"
        "d /var/lib/sabnzbd 0755 media-podman media-services -"
        "d /var/lib/deluge 0755 media-podman media-services -"
        "d /var/lib/emby 0755 media-podman media-services -"
        "d /var/lib/gluetun 0755 media-podman media-services -"
        "d /var/lib/qbittorrent 0755 media-podman media-services -"
      ];

      # Enable lingering for media-podman
      systemd.services.enable-linger-media-podman = {
        description = "Enable lingering for media-podman user";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger media-podman";
        };
      };

      # Create gluetun env file from secrets
      systemd.services.gluetun-env-setup = {
        description = "Create Gluetun environment file from secrets";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          VPNUSER=$(sed -n "1p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
          VPNPASS=$(sed -n "2p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
          echo "OPENVPN_USER=$VPNUSER" > /run/secrets/nordvpn-credentials-env
          echo "OPENVPN_PASSWORD=$VPNPASS" >> /run/secrets/nordvpn-credentials-env
          chmod 644 /run/secrets/nordvpn-credentials-env
        '';
      };
    })

    # Utility containers (run as utils-podman user)
    (mkIf config.services.quadlet-utils.enable {
      # Home-manager configuration for utils-podman user
      home-manager.users.utils-podman = { pkgs, ... }: {
        imports = [ quadlet-nix.homeManagerModules.quadlet ];

        home.stateVersion = "25.05";
        home.enableNixpkgsReleaseCheck = false;
        home.homeDirectory = "/var/lib/utils-podman";
        home.username = "utils-podman";

        # Quadlet container definitions
        virtualisation.quadlet.containers = {
          # Uptime Kuma - Monitoring
          uptime-kuma = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/louislam/uptime-kuma:latest";
              publishPorts = [ "3344:3001" ];
              volumes = [
                "/var/lib/uptime-kuma:/app/data:rw"
              ];
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Restic REST Server
          restic-rest-server = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/restic/rest-server:latest";
              publishPorts = [ "8000:8000" ];
              volumes = [
                "/var/lib/restic:/data:rw"
              ];
              environments = {
                OPTIONS = "--no-auth";
              };
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Ollama LLM Runtime
          ollama = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/ollama/ollama:latest";
              publishPorts = [ "11434:11434" ];
              volumes = [
                "/var/lib/ollama:/root/.ollama:rw"
              ];
              devices = [ "/dev/dri:/dev/dri" "nvidia.com/gpu=all" ];
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Open WebUI for Ollama
          open-webui = {
            autoStart = true;
            containerConfig = {
              image = "ghcr.io/open-webui/open-webui:main";
              publishPorts = [ "3003:8080" ];
              volumes = [
                "/var/lib/open-webui:/app/backend/data:rw"
              ];
              environments = {
                OLLAMA_BASE_URL = "http://host.containers.internal:11434";
              };
              labels = [ "io.containers.autoupdate=registry" ];
              logDriver = "journald";
              addHosts = [ "host.containers.internal:host-gateway" ];
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
            unitConfig = {
              After = [ "ollama.service" ];
            };
          };

          # ComfyUI - Stable Diffusion Node Editor
          comfyui = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/yanwk/comfyui-boot:cu126-slim";
              publishPorts = [ "8188:8188" ];
              volumes = [
                "/var/lib/comfyui:/root:rw"
              ];
              devices = [ "nvidia.com/gpu=all" ];
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Redis for Paperless-ngx
          paperless-redis = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/library/redis:7-alpine";
              publishPorts = [ "6379:6379" ];
              volumes = [
                "/var/lib/paperless-redis:/data:rw"
              ];
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

          # Paperless-ngx - Document Management
          paperless-ngx = {
            autoStart = true;
            containerConfig = {
              image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
              publishPorts = [ "8010:8000" ];
              volumes = [
                "/var/lib/paperless-ngx/data:/usr/src/paperless/data:rw"
                "/var/lib/paperless-ngx/media:/usr/src/paperless/media:rw"
                "/var/lib/paperless-ngx/export:/usr/src/paperless/export:rw"
                "/var/lib/paperless-ngx/consume:/usr/src/paperless/consume:rw"
              ];
              environments = {
                PAPERLESS_REDIS = "redis://host.containers.internal:6379";
                PAPERLESS_OCR_LANGUAGE = "eng";
                PAPERLESS_OCR_LANGUAGES = "eng+fra+spa+ukr+rus";
                PAPERLESS_FILENAME_FORMAT = "{created}-{correspondent}-{title}";
                PAPERLESS_TIME_ZONE = "Europe/Dublin";
                PAPERLESS_URL = "https://paperless.fer.xyz";
                PAPERLESS_CONSUMER_POLLING = "30";
              };
              environmentFiles = [ "/run/secrets/paperless-env" ];
              autoUpdate = "registry";
              logDriver = "journald";
              addHosts = [ "host.containers.internal:host-gateway" ];
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
            unitConfig = {
              After = [ "paperless-redis.service" ];
              Requires = [ "paperless-redis.service" ];
            };
          };

          # Pure-FTPd for Paperless document ingestion
          pure-ftpd = {
            autoStart = true;
            containerConfig = {
              image = "docker.io/crazymax/pure-ftpd:latest";
              publishPorts = [
                "29999:2100"
                "30000-30009:30000-30009"
              ];
              volumes = [
                "/var/lib/pure-ftpd:/data:rw"
                "/var/lib/paperless-ngx/consume:/home/admin:rw"
              ];
              environments = {
                AUTH_METHOD = "puredb";
                SECURE_MODE = "true";
                PASSIVE_PORT_RANGE = "30000:30009";
              };
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };

        };
      };

      # System-level setup for utils-podman user
      systemd.tmpfiles.rules = [
        "d /run/user/13107 0700 utils-podman utils-podman -"
        "d /var/lib/uptime-kuma 0755 utils-podman utils-podman -"
        "d /var/lib/restic 0755 utils-podman utils-podman -"
        "d /var/lib/ollama 0755 utils-podman utils-podman -"
        "d /var/lib/open-webui 0755 utils-podman utils-podman -"
        "d /var/lib/comfyui 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-redis 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-ngx 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-ngx/data 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-ngx/media 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-ngx/export 0755 utils-podman utils-podman -"
        "d /var/lib/paperless-ngx/consume 0755 utils-podman utils-podman -"
        "d /var/lib/pure-ftpd 0755 utils-podman utils-podman -"
      ];

      # Create paperless env file from secrets
      systemd.services.paperless-env-setup = {
        description = "Create Paperless environment file from secrets";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          SECRET_KEY=$(cat /run/secrets/paperless-secret-key | tr -d "\n\r")
          echo "PAPERLESS_SECRET_KEY=$SECRET_KEY" > /run/secrets/paperless-env
          chmod 644 /run/secrets/paperless-env
        '';
      };

      # Enable lingering for utils-podman
      systemd.services.enable-linger-utils-podman = {
        description = "Enable lingering for utils-podman user";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger utils-podman";
        };
      };
    })
  ];
}
;
}
