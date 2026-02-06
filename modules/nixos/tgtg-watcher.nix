# TooGoodToGo Watcher service
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  # Dockerfile for building tgtg-watcher from source
  dockerfile = pkgs.writeText "Containerfile" ''
    FROM node:18-alpine
    RUN apk add --no-cache tzdata git
    WORKDIR /home/node/app
    RUN git clone https://github.com/marklagendijk/node-toogoodtogo-watcher.git /home/node/app
    RUN npm ci --production
    RUN mkdir -p /home/node/.config/toogoodtogo-watcher-nodejs && \
        chown -R node:node /home/node/
    USER node
    VOLUME /home/node/.config/toogoodtogo-watcher-nodejs
    ENTRYPOINT [ "node", "index.js" ]
    CMD ["watch"]
  '';
in
{
  options.services.tgtg-watcher = {
    enable = mkEnableOption "TooGoodToGo Watcher service";

    configPath = mkOption {
      type = types.path;
      default = "/var/lib/tgtg";
      description = "Path to store TooGoodToGo Watcher configuration";
    };
  };

  config = mkIf config.services.tgtg-watcher.enable {
    # Create tmpfiles directory
    systemd.tmpfiles.rules = [
      "d ${config.services.tgtg-watcher.configPath} 0755 root root -"
    ];

    # Build the container image using quadlet
    virtualisation.quadlet.builds.tgtg-watcher = {
      buildConfig = {
        file = dockerfile.outPath;
        tag = "localhost/tgtg-watcher:latest";
      };
    };

    # TooGoodToGo watcher container using quadlet
    virtualisation.quadlet.containers.tgtg-watcher = {
      autoStart = true;
      containerConfig = {
        image = config.virtualisation.quadlet.builds.tgtg-watcher.ref;
        volumes = [
          "${config.services.tgtg-watcher.configPath}:/home/node/.config/toogoodtogo-watcher-nodejs:rw"
        ];
        environments = {
          TZ = "Europe/Dublin";
        };
        podmanArgs = [ "--log-driver=journald" ];
        exec = "watch";
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };
  };
}
