# Tdarr distributed transcoding system
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  # Common restart configuration for podman services (serviceConfig)
  commonRestartConfig = {
    Restart = "always";
    RestartSec = "15min";
  };

  # Common unit configuration for podman services
  commonUnitConfig = {
    StartLimitIntervalSec = 0;
  };
in

{
  options.services.tdarr = {
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

  config = mkIf config.services.tdarr.enable {
    # Tdarr Server
    systemd.services.tdarr-server = mkIf config.services.tdarr.server.enable {
      description = "Tdarr Transcoding Server";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.podman ];

      unitConfig = commonUnitConfig;

      serviceConfig = commonRestartConfig // {
        Type = "simple";
        User = config.services.tdarr.user;
        Group = config.services.tdarr.group;
        TimeoutStartSec = "5min";

        # Resource limits - low priority
        MemoryMax = "2G";
        CPUWeight = 50;
        IOWeight = 50;
        Nice = 15;

        Environment = [
          "HOME=/var/lib/${config.services.tdarr.user}"
          "XDG_RUNTIME_DIR=/run/user/13106"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
        ];

        ExecStartPre = [
          "+${pkgs.coreutils}/bin/mkdir -p ${config.services.tdarr.transcodeCache}"
          "+${pkgs.coreutils}/bin/chown -R 13106:13100 ${config.services.tdarr.transcodeCache}"
          "-${pkgs.podman}/bin/podman rm -f tdarr-server"
        ];

        ExecStart = ''
          ${pkgs.podman}/bin/podman run --rm --name tdarr-server \
            --label io.containers.autoupdate=registry \
            --log-driver=journald \
            -p ${toString config.services.tdarr.server.webPort}:8265 \
            -p ${toString config.services.tdarr.server.serverPort}:8266 \
            ${optionalString config.services.tdarr.server.internalNode "-p ${toString config.services.tdarr.server.nodePort}:8264"} \
            -v /var/lib/tdarr/server:/app/server:rw \
            -v /var/lib/tdarr/configs:/app/configs:rw \
            -v /var/lib/tdarr/logs:/app/logs:rw \
            ${concatStringsSep " " (mapAttrsToList (name: path: "-v ${path}:/${name}:rw,rslave") config.services.tdarr.mediaDirectories)} \
            -v ${config.services.tdarr.transcodeCache}:/temp:rw \
            -e serverIP=0.0.0.0 \
            -e serverPort=${toString config.services.tdarr.server.serverPort} \
            -e webUIPort=${toString config.services.tdarr.server.webPort} \
            -e internalNode=${if config.services.tdarr.server.internalNode then "true" else "false"} \
            -e nodeID=InternalNode \
            -e nodeIP=0.0.0.0 \
            -e nodePort=${toString config.services.tdarr.server.nodePort} \
            -e PUID=0 \
            -e PGID=0 \
            -e TZ=Europe/Dublin \
            ghcr.io/haveagitgat/tdarr:latest
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 tdarr-server";
      };
    };

    # Tdarr Node
    systemd.services.tdarr-node = mkIf config.services.tdarr.node.enable {
      description = "Tdarr Transcoding Node";
      after = [ "network-online.target" ] ++ optional config.services.tdarr.server.enable "tdarr-server.service";
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.podman ];

      unitConfig = commonUnitConfig;

      serviceConfig = commonRestartConfig // {
        Type = "simple";
        User = config.services.tdarr.user;
        Group = config.services.tdarr.group;
        TimeoutStartSec = "5min";

        # Resource limits - low priority, can use more resources for transcoding
        MemoryMax = "8G";
        CPUWeight = 20;
        IOWeight = 50;
        Nice = 19;

        Environment = [
          "HOME=/var/lib/${config.services.tdarr.user}"
          "XDG_RUNTIME_DIR=/run/user/13106"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
        ];

        ExecStartPre = [
          "+${pkgs.coreutils}/bin/mkdir -p ${config.services.tdarr.transcodeCache}"
          "+${pkgs.coreutils}/bin/chown -R 13106:13100 ${config.services.tdarr.transcodeCache}"
          "-${pkgs.podman}/bin/podman rm -f tdarr-node"
        ];

        ExecStart = ''
          ${pkgs.podman}/bin/podman run --rm --name tdarr-node \
            --label io.containers.autoupdate=registry \
            --log-driver=journald \
            -p ${toString config.services.tdarr.node.nodePort}:8267 \
            -v /var/lib/tdarr/configs:/app/configs:rw \
            -v /var/lib/tdarr/logs:/app/logs:rw \
            ${concatStringsSep " " (mapAttrsToList (name: path: "-v ${path}:/${name}:rw,rslave") config.services.tdarr.mediaDirectories)} \
            -v ${config.services.tdarr.transcodeCache}:/temp:rw \
            --device /dev/dri:/dev/dri \
            -e serverIP=${config.services.tdarr.node.serverIP} \
            -e serverPort=${toString config.services.tdarr.node.serverPort} \
            -e nodeIP=0.0.0.0 \
            -e nodeID=${config.services.tdarr.node.nodeId} \
            -e nodePort=${toString config.services.tdarr.node.nodePort} \
            -e PUID=0 \
            -e PGID=0 \
            -e TZ=Europe/Dublin \
            ghcr.io/haveagitgat/tdarr_node:latest
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 tdarr-node";
      };
    };

    # Firewall configuration
    networking.firewall.allowedTCPPorts = mkMerge [
      (mkIf config.services.tdarr.server.enable [
        config.services.tdarr.server.webPort
        config.services.tdarr.server.serverPort
      ])
      (mkIf (config.services.tdarr.server.enable && config.services.tdarr.server.internalNode) [
        config.services.tdarr.server.nodePort
      ])
      (mkIf config.services.tdarr.node.enable [
        config.services.tdarr.node.nodePort
      ])
    ];

    # Tmpfiles rules for directories
    systemd.tmpfiles.rules = [
      "d /var/lib/tdarr 0755 13106 13100 -"
      "d /var/lib/tdarr/server 0755 13106 13100 -"
      "d /var/lib/tdarr/configs 0755 13106 13100 -"
      "d /var/lib/tdarr/logs 0755 13106 13100 -"
      "d ${config.services.tdarr.transcodeCache} 0777 13106 13100 -"
    ];
  };
}
