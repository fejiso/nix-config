{ ... }: {
  flake.modules.nixos.openclaw =
# OpenClaw - Self-hosted AI assistant - using rootless podman
{ config, lib, pkgs, quadlet-nix, ... }:

with lib;

let
  cfg = config.services.openclaw;
  tokenFile = config.sops.secrets.openclaw-gateway-token.path;
  openrouterKeyFile = config.sops.secrets.openrouter-api-key.path;
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
      default = "openrouter/meta-llama/llama-3.3-70b-instruct:free";
      description = "Default LLM model to use";
    };
  };

  config = mkIf cfg.enable {
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

    # Create environment file from secrets
    systemd.services.openclaw-env-setup = {
      description = "Create OpenClaw environment file from secrets";
      wantedBy = [ "multi-user.target" ];
      after = [ "sops-nix.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        mkdir -p /run/secrets
        GATEWAY_TOKEN=$(cat ${tokenFile})
        OPENROUTER_KEY=$(cat ${openrouterKeyFile})
        cat > /run/secrets/openclaw-env << EOF
        OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
        OPENROUTER_API_KEY=$OPENROUTER_KEY
        EOF
        chmod 600 /run/secrets/openclaw-env
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
          environmentFiles = [ "/run/secrets/openclaw-env" ];
          autoUpdate = "registry";
          logDriver = "journald";
        };
        serviceConfig = {
          Restart = "always";
          RestartSec = "900";
        };
        unitConfig = {
          After = [ "openclaw-env-setup.service" ];
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
