{ ... }: {
  flake.modules.nixos.tdarr =
# Tdarr distributed transcoding system - using rootless podman via home-manager quadlet
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  quadlet-nix,
  ...
}:

with lib;

{
  options.services.tdarr-podman = {
    enable = mkEnableOption "Tdarr transcoding server";

    server = {
      enable = mkEnableOption "Tdarr server" // { default = true; };

      webPort = mkOption {
        type = types.port;
        default = 8265;
        description = "WebUI port";
      };

      serverPort = mkOption {
        type = types.port;
        default = 8266;
        description = "Server communication port";
      };

      internalNode = mkOption {
        type = types.bool;
        default = false;
        description = "Enable internal node within server container";
      };

      nodePort = mkOption {
        type = types.port;
        default = 8264;
        description = "Internal node port";
      };
    };

    node = {
      enable = mkEnableOption "Tdarr worker node";

      nodeId = mkOption {
        type = types.str;
        default = "${config.networking.hostName}_tdarr_node";
        description = "Node ID name";
      };

      nodePort = mkOption {
        type = types.port;
        default = 8267;
        description = "Node communication port";
      };

      serverIP = mkOption {
        type = types.str;
        default = "127.0.0.1";
        description = "Tdarr server IP address";
      };

      serverPort = mkOption {
        type = types.port;
        default = 8266;
        description = "Tdarr server port";
      };
    };

    user = mkOption {
      type = types.str;
      default = "media-podman";
      description = "User to run tdarr services as";
    };

    group = mkOption {
      type = types.str;
      default = "media-services";
      description = "Group to run tdarr services as";
    };

    mediaDirectories = mkOption {
      type = types.attrs;
      default = {
        tv = "/mnt/user/Series";
        movies = "/mnt/user/Movies";
        music = "/mnt/user/Music";
      };
      description = "Media directories to mount";
    };

    transcodeCache = mkOption {
      type = types.str;
      default = "/var/lib/tdarr/transcode-cache";
      description = "Directory for transcode temporary files";
    };
  };

  config = mkIf config.services.tdarr-podman.enable {
    # Home-manager configuration for media-podman user (tdarr containers)
    home-manager.users.media-podman = { pkgs, ... }: {
      imports = [ quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "25.05";
      home.enableNixpkgsReleaseCheck = false;
      home.homeDirectory = "/var/lib/media-podman";
      home.username = "media-podman";

      virtualisation.quadlet.containers = mkMerge [
        # Tdarr Server
        (mkIf config.services.tdarr-podman.server.enable {
          tdarr-server = {
            autoStart = true;
            containerConfig = {
              image = "ghcr.io/haveagitgat/tdarr:latest";
              publishPorts = [
                "${toString config.services.tdarr-podman.server.webPort}:8265"
                "${toString config.services.tdarr-podman.server.serverPort}:8266"
              ] ++ optional config.services.tdarr-podman.server.internalNode
                "${toString config.services.tdarr-podman.server.nodePort}:8264";
              volumes = [
                "/var/lib/tdarr/server:/app/server:rw"
                "/var/lib/tdarr/configs:/app/configs:rw"
                "/var/lib/tdarr/logs:/app/logs:rw"
                "${config.services.tdarr-podman.transcodeCache}:/temp:rw"
              ] ++ (mapAttrsToList (name: path: "${path}:/${name}:rw,rslave") config.services.tdarr-podman.mediaDirectories);
              environments = {
                serverIP = "0.0.0.0";
                serverPort = toString config.services.tdarr-podman.server.serverPort;
                webUIPort = toString config.services.tdarr-podman.server.webPort;
                internalNode = if config.services.tdarr-podman.server.internalNode then "true" else "false";
                nodeID = "InternalNode";
                nodeIP = "0.0.0.0";
                nodePort = toString config.services.tdarr-podman.server.nodePort;
                PUID = "0";
                PGID = "0";
                TZ = "Europe/Dublin";
              };
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
          };
        })

        # Tdarr Node
        (mkIf config.services.tdarr-podman.node.enable {
          tdarr-node = {
            autoStart = true;
            containerConfig = {
              image = "ghcr.io/haveagitgat/tdarr_node:latest";
              publishPorts = [ "${toString config.services.tdarr-podman.node.nodePort}:8267" ];
              volumes = [
                "/var/lib/tdarr/configs:/app/configs:rw"
                "/var/lib/tdarr/logs:/app/logs:rw"
                "${config.services.tdarr-podman.transcodeCache}:/temp:rw"
              ] ++ (mapAttrsToList (name: path: "${path}:/${name}:rw,rslave") config.services.tdarr-podman.mediaDirectories);
              devices = [ "/dev/dri:/dev/dri" ];
              environments = {
                serverIP = config.services.tdarr-podman.node.serverIP;
                serverPort = toString config.services.tdarr-podman.node.serverPort;
                nodeIP = "0.0.0.0";
                nodeID = config.services.tdarr-podman.node.nodeId;
                nodePort = toString config.services.tdarr-podman.node.nodePort;
                PUID = "0";
                PGID = "0";
                TZ = "Europe/Dublin";
              };
              autoUpdate = "registry";
              logDriver = "journald";
            };
            serviceConfig = {
              Restart = "always";
              RestartSec = "900";
            };
            unitConfig = mkIf config.services.tdarr-podman.server.enable {
              After = [ "tdarr-server.service" ];
            };
          };
        })
      ];
    };

    # Firewall — tdarr server/node traffic is between netbird peers only.
    networking.firewall.interfaces.wt0.allowedTCPPorts = mkMerge [
      (mkIf config.services.tdarr-podman.server.enable [
        config.services.tdarr-podman.server.webPort
        config.services.tdarr-podman.server.serverPort
      ])
      (mkIf (config.services.tdarr-podman.server.enable && config.services.tdarr-podman.server.internalNode) [
        config.services.tdarr-podman.server.nodePort
      ])
      (mkIf config.services.tdarr-podman.node.enable [
        config.services.tdarr-podman.node.nodePort
      ])
    ];

    # Tmpfiles rules for directories
    systemd.tmpfiles.rules = [
      "d /var/lib/tdarr 0755 media-podman media-services -"
      "d /var/lib/tdarr/server 0755 media-podman media-services -"
      "d /var/lib/tdarr/configs 0755 media-podman media-services -"
      "d /var/lib/tdarr/logs 0755 media-podman media-services -"
      "d ${config.services.tdarr-podman.transcodeCache} 0777 media-podman media-services -"
    ];
  };
}
;
}
