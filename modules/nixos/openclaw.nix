# OpenClaw - Self-hosted AI assistant
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.openclaw;
  tokenFile = config.sops.secrets.openclaw-gateway-token.path;
in {
  options.services.openclaw = {
    enable = mkEnableOption "OpenClaw AI assistant";

    port = mkOption {
      type = types.port;
      default = 3080;
      description = "Port for OpenClaw gateway";
    };

    dataDir = mkOption {
      type = types.str;
      default = "/var/lib/openclaw";
      description = "Directory for OpenClaw data";
    };

    model = mkOption {
      type = types.str;
      default = "anthropic/claude-sonnet-4";
      description = "Default LLM model to use";
    };
  };

  config = mkIf cfg.enable {
    # Create data directory
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 root root -"
      "d ${cfg.dataDir}/workspace 0755 root root -"
    ];

    # OpenClaw systemd service using podman
    systemd.services.openclaw = {
      description = "OpenClaw AI Assistant";
      after = [ "network-online.target" "sops-nix.service" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      path = [ pkgs.podman ];

      script = ''
        GATEWAY_TOKEN=$(cat ${tokenFile})
        exec ${pkgs.podman}/bin/podman run --rm --name openclaw \
          --label io.containers.autoupdate=registry \
          -p ${toString cfg.port}:3080 \
          -v ${cfg.dataDir}:/root/.openclaw:rw \
          -e OPENCLAW_GATEWAY_PORT=3080 \
          -e OPENCLAW_GATEWAY_TOKEN="$GATEWAY_TOKEN" \
          -e OPENCLAW_AGENT_MODEL=${cfg.model} \
          ghcr.io/openclaw/openclaw:latest
      '';

      serviceConfig = {
        Type = "simple";
        Restart = "always";
        RestartSec = "30";
        ExecStartPre = "-${pkgs.podman}/bin/podman rm -f openclaw";
        ExecStop = "${pkgs.podman}/bin/podman stop -t 10 openclaw";
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
