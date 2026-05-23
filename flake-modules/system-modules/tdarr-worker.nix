flakeArgs: {
  flake.modules.nixos.tdarr-worker =
{ config, lib, pkgs, ... }:

with lib;

{
  imports = [
    flakeArgs.config.flake.modules.nixos.tdarr
    flakeArgs.config.flake.modules.nixos.media-podman
  ];

  options.services.tdarr-worker = {
    enable = mkEnableOption "Tdarr worker node with all dependencies";

    serverEnabled = mkOption {
      type = types.bool;
      default = false;
      description = "Also enable Tdarr server on this host";
    };

    nodeId = mkOption {
      type = types.str;
      default = "${config.networking.hostName}_worker";
      description = "Node ID name";
    };

    serverIP = mkOption {
      type = types.str;
      default = "butthead.netbird.cloud";
      description = "Tdarr server address";
    };

    serverPort = mkOption {
      type = types.port;
      default = 8266;
      description = "Tdarr server port";
    };

    mediaDirectories = mkOption {
      type = types.attrs;
      default = {
        tv = "/mnt/Series";
        movies = "/mnt/Movies";
      };
      description = "Media directories to mount";
    };

    transcodeCache = mkOption {
      type = types.str;
      default = "/var/lib/tdarr/transcode-cache";
      description = "Directory for transcode temporary files";
    };
  };

  config = mkIf config.services.tdarr-worker.enable {
    services.tdarr = {
      enable = true;
      server.enable = config.services.tdarr-worker.serverEnabled;
      node = {
        enable = true;
        nodeId = config.services.tdarr-worker.nodeId;
        serverIP = config.services.tdarr-worker.serverIP;
        serverPort = config.services.tdarr-worker.serverPort;
      };
      mediaDirectories = config.services.tdarr-worker.mediaDirectories;
      transcodeCache = config.services.tdarr-worker.transcodeCache;
    };

    # Enable podman for quadlet containers
    virtualisation.podman = {
      enable = true;
      dockerCompat = false;
    };
  };
}
;
}
