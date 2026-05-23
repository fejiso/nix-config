{ ... }: {
  flake.modules.nixos.tgtg-watcher =
# TooGoodToGo Watcher service - using rootless podman via home-manager quadlet
{
  config,
  lib,
  pkgs,
  quadlet-nix,
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
      "d ${config.services.tgtg-watcher.configPath} 0755 utils-podman utils-podman -"
    ];

    # Build the Docker image from source using podman build (system service)
    systemd.services.tgtg-watcher-build = {
      description = "Build TooGoodToGo Watcher Docker Image";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "utils-podman";
        Group = "utils-podman";
        Environment = [
          "HOME=/var/lib/utils-podman"
          "XDG_RUNTIME_DIR=/run/user/13107"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
        ];
      };
      script = ''
        ${pkgs.podman}/bin/podman build -t localhost/tgtg-watcher:latest -f ${dockerfile} /var/empty
      '';
    };

    # Home-manager configuration for utils-podman user (tgtg-watcher container)
    home-manager.users.utils-podman = { pkgs, ... }: {
      imports = [ quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "25.05";
      home.enableNixpkgsReleaseCheck = false;
      home.homeDirectory = "/var/lib/utils-podman";
      home.username = "utils-podman";

      virtualisation.quadlet.containers.tgtg-watcher = {
        autoStart = true;
        containerConfig = {
          image = "localhost/tgtg-watcher:latest";
          volumes = [
            "${config.services.tgtg-watcher.configPath}:/home/node/.config/toogoodtogo-watcher-nodejs:rw"
          ];
          environments = {
            TZ = "Europe/Dublin";
          };
          logDriver = "journald";
          exec = "watch";
        };
        serviceConfig = {
          Restart = "always";
          RestartSec = "900";
        };
        unitConfig = {
          # Wait for the build to complete
          After = [ "tgtg-watcher-build.service" ];
        };
      };
    };
  };
}
;
}
