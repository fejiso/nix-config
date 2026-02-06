# OpenClaw - Self-hosted AI assistant
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.openclaw;
  tokenFile = config.sops.secrets.openclaw-gateway-token.path;
  anthropicKeyFile = config.sops.secrets.anthropic-api-key.path;
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

    # Create environment file from secrets
    systemd.services.openclaw-env-setup = {
      description = "Create OpenClaw environment file from secrets";
      wantedBy = [ "multi-user.target" ];
      before = [ "openclaw.service" ];
      after = [ "sops-nix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/secrets
        GATEWAY_TOKEN=$(cat ${tokenFile})
        ANTHROPIC_KEY=$(cat ${anthropicKeyFile})
        cat > /run/secrets/openclaw-env << EOF
        OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
        ANTHROPIC_API_KEY=$ANTHROPIC_KEY
        EOF
        chmod 600 /run/secrets/openclaw-env
      '';
    };

    # OpenClaw quadlet container
    virtualisation.quadlet.containers.openclaw = {
      autoStart = true;
      containerConfig = {
        image = "ghcr.io/openclaw/openclaw:latest";
        publishPorts = [ "${toString cfg.port}:3080" ];
        volumes = [
          "${cfg.dataDir}:/root/.openclaw:rw"
        ];
        environments = {
          OPENCLAW_GATEWAY_PORT = "3080";
          OPENCLAW_AGENT_MODEL = cfg.model;
        };
        environmentFiles = [ "/run/secrets/openclaw-env" ];
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
      unitConfig = {
        After = [ "openclaw-env-setup.service" "sops-nix.service" ];
        Requires = [ "openclaw-env-setup.service" ];
      };
    };

    # Open firewall port
    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
