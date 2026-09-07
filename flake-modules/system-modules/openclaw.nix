{ ... }: {
  flake.modules.nixos.openclaw =
# OpenClaw - Self-hosted AI assistant - using rootless podman
{ config, lib, pkgs, inputs, quadlet-nix, ... }:

with lib;

let
  cfg = config.services.openclaw;
  tokenFile = config.sops.secrets.openclaw-gateway-token.path;
  openrouterKeyFile = config.sops.secrets.openrouter-api-key.path;
  opencodegoKeyFile = config.sops.secrets.opencodego-api-key.path;
  kimiKeyFile = config.sops.secrets.kimi-api-key.path;

  # Declarative gateway config. NO secrets in here: provider API keys are
  # SecretRefs resolved from the process env (written to /run/openclaw/env by
  # openclaw-env-setup from sops), and the Telegram bot token uses the
  # TELEGRAM_BOT_TOKEN env fallback. Installed to ${dataDir}/openclaw.json
  # (the container mounts dataDir at /root/.openclaw) on every deploy;
  # channels.telegram.configWrites=false keeps runtime writes from fighting it.
  openclawJson = pkgs.writeText "openclaw.json" (builtins.toJSON ({
    gateway.mode = "local";
    models.providers = {
      # OpenCode Zen (https://opencode.ai/zen) — free models as the baseline.
      opencode = {
        baseUrl = "https://opencode.ai/zen/v1";
        api = "openai-completions";
        apiKey = { source = "env"; id = "OPENCODE_ZEN_API_KEY"; };
        models = map (id: {
          inherit id;
          name = id;
          api = "openai-completions";
          contextWindow = 200000;
        }) [ "big-pickle" "nemotron-3-ultra-free" "mimo-v2.5-free" ];
      };
      # OpenRouter fallback.
      openrouter = {
        baseUrl = "https://openrouter.ai/api/v1";
        api = "openai-completions";
        apiKey = { source = "env"; id = "OPENROUTER_API_KEY"; };
        models = [{
          id = "deepseek/deepseek-v4-flash";
          name = "DeepSeek V4 Flash";
          api = "openai-completions";
          contextWindow = 1000000;
        }];
      };
    };
    agents.defaults.model = {
      primary = cfg.model;
      fallbacks = cfg.modelFallbacks;
    };
  } // optionalAttrs cfg.telegram.enable {
    channels.telegram = {
      enabled = true;
      # allowlist + the owner's numeric user ID: the agent can DM the owner
      # by default, everyone else is rejected.
      dmPolicy = "allowlist";
      allowFrom = cfg.telegram.allowFrom;
      configWrites = false;
    };
  }));
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
      default = "opencode/big-pickle";
      description = "Primary LLM model (provider/model-id from openclaw.json)";
    };

    modelFallbacks = mkOption {
      type = types.listOf types.str;
      default = [ ];
      description = "Fallback models tried in order when the primary fails";
    };

    telegram = {
      enable = mkEnableOption "Telegram channel";
      allowFrom = mkOption {
        type = types.listOf types.int;
        default = [ ];
        description = "Numeric Telegram user IDs allowed to DM the bot";
      };
    };
  };

  config = mkIf cfg.enable {
    # Telegram bot token, host-local (only evaluated when the channel is on).
    # Add the key with: sops secrets/openclaw.yaml  ->  telegram_bot_token: <token>
    sops.secrets = mkIf cfg.telegram.enable {
      openclaw-telegram-bot-token = {
        sopsFile = "${inputs.self}/secrets/openclaw.yaml";
        key = "telegram_bot_token";
        mode = "0444";
      };
    };

    # Enable podman for rootless containers
    virtualisation.podman = {
      enable = true;
      autoPrune.enable = true;
      defaultNetwork.settings.dns_enabled = true;
    };

    # Create openclaw user for rootless podman
    users.users.openclaw = {
      isSystemUser = true;
      group = "openclaw";
      uid = 13108;
      home = "/var/lib/openclaw";
      createHome = true;
      subUidRanges = [{ startUid = 500000; count = 65536; }];
      subGidRanges = [{ startGid = 500000; count = 65536; }];
    };
    users.groups.openclaw = {
      gid = 13108;
    };

    # Create data directory and runtime dir
    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0755 openclaw openclaw -"
      "d ${cfg.dataDir}/workspace 0755 openclaw openclaw -"
      "d /run/user/13108 0700 openclaw openclaw -"
    ];

    # Enable lingering for openclaw user
    systemd.services.enable-linger-openclaw = {
      description = "Enable lingering for openclaw user";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger openclaw";
      };
    };

    # Create environment file from secrets (outside /run/secrets to avoid sops-nix cleanup)
    systemd.services.openclaw-env-setup = {
      description = "Create OpenClaw environment file from secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ "sops-nix.service" ];
      restartIfChanged = true;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/openclaw
        GATEWAY_TOKEN=$(cat ${tokenFile})
        OPENROUTER_KEY=$(cat ${openrouterKeyFile})
        ZEN_KEY=$(cat ${opencodegoKeyFile})
        KIMI_KEY=$(cat ${kimiKeyFile})
        ${optionalString cfg.telegram.enable ''
        TELEGRAM_TOKEN=$(cat ${config.sops.secrets.openclaw-telegram-bot-token.path})
        ''}
        {
          echo "OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN"
          echo "OPENROUTER_API_KEY=$OPENROUTER_KEY"
          echo "OPENCODE_ZEN_API_KEY=$ZEN_KEY"
          echo "KIMI_API_KEY=$KIMI_KEY"
          echo "MOONSHOT_API_KEY=$KIMI_KEY"
          ${optionalString cfg.telegram.enable ''
          echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_TOKEN"
          ''}
        } > /run/openclaw/env
        chown openclaw:openclaw /run/openclaw/env
        chmod 600 /run/openclaw/env

        # Install the declarative gateway config (secrets stay in env vars).
        cp ${openclawJson} ${cfg.dataDir}/openclaw.json
        chown openclaw:openclaw ${cfg.dataDir}/openclaw.json
      '';
    };

    # Home-manager configuration for openclaw user
    home-manager.users.openclaw = { pkgs, ... }: {
      imports = [ quadlet-nix.homeManagerModules.quadlet ];

      home.stateVersion = "25.05";
      home.enableNixpkgsReleaseCheck = false;
      home.homeDirectory = "/var/lib/openclaw";
      home.username = "openclaw";

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
          environmentFiles = [ "/run/openclaw/env" ];
          autoUpdate = "registry";
          logDriver = "journald";
        };
        serviceConfig = {
          ExecStartPre = [
            "${pkgs.coreutils}/bin/timeout 120 ${pkgs.bash}/bin/bash -c 'while [ ! -f /run/openclaw/env ]; do sleep 1; done'"
          ];
          Restart = "always";
          RestartSec = "900";
        };
        unitConfig = {
          After = [ "openclaw-env-setup.service" ];
          Wants = [ "openclaw-env-setup.service" ];
        };
      };
    };

    # Open only on the netbird mesh; butthead's nginx-proxy-manager
    # reverse-proxies for external access.
    networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.port ];
  };
}
;
}
