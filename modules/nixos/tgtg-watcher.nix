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
  dockerfile = pkgs.writeText "Dockerfile" ''
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

    # Build the Docker image from source using podman build
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

    # TooGoodToGo watcher service
    systemd.services.tgtg-watcher = {
      description = "TooGoodToGo Watcher";
      after = [ "network-online.target" "tgtg-watcher-build.service" ];
      wants = [ "network-online.target" ];
      requires = [ "tgtg-watcher-build.service" ];
      wantedBy = [ "multi-user.target" ];

      unitConfig = commonUnitConfig;

      serviceConfig = commonRestartConfig // {
        Type = "simple";
        User = "utils-podman";
        Group = "utils-podman";
        TimeoutStartSec = "5min";

        # Resource limits
        CPUQuota = "50%";
        MemoryMax = "500M";
        IOWeight = 50;

        Environment = [
          "HOME=/var/lib/utils-podman"
          "XDG_RUNTIME_DIR=/run/user/13107"
          "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
        ];

        ExecStartPre = [
          "-${pkgs.podman}/bin/podman rm -f tgtg-watcher"
        ];

        ExecStart = ''
          ${pkgs.podman}/bin/podman run --rm --name tgtg-watcher \
            --log-driver=journald \
            --userns=keep-id:uid=1000,gid=1000 \
            -v ${config.services.tgtg-watcher.configPath}:/home/node/.config/toogoodtogo-watcher-nodejs:rw \
            -e TZ=Europe/Dublin \
            localhost/tgtg-watcher:latest \
            watch
        '';

        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 tgtg-watcher";
      };
    };
  };
}
