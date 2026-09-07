{ ... }: {
  flake.modules.homeManager.silverbullet =
# Silverbullet PKM as a systemd USER service (used on hierro and devdesktop —
# no system service). Basic auth comes from SB_USER=user:password, loaded from
# a sops-managed env file so no credentials land in the nix store.
# Create the secret with:
#   sops secrets/silverbullet.yaml   ->   sb_user_env: "SB_USER=<user>:<password>"
{ config, pkgs, lib, inputs, ... }:

with lib;

let
  cfg = config.services.silverbullet;
in {
  options.services.silverbullet = {
    enable = mkEnableOption "Silverbullet PKM (user service)";

    host = mkOption {
      type = types.str;
      default = "127.0.0.1";
      description = "The address to bind to";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "The port to listen on";
    };

    spaceDir = mkOption {
      type = types.str;
      default = "${config.home.homeDirectory}/silverbullet";
      description = "The Silverbullet space (notes directory)";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.silverbullet ];

    sops.secrets.silverbullet-auth = {
      sopsFile = "${inputs.self}/secrets/silverbullet.yaml";
      key = "sb_user_env";
      mode = "0600";
    };

    systemd.user.services.silverbullet = {
      Unit = {
        Description = "Silverbullet PKM";
        After = [ "network.target" ];
      };
      Service = {
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p '${cfg.spaceDir}'";
        ExecStart = "${pkgs.silverbullet}/bin/silverbullet --port ${toString cfg.port} --hostname '${cfg.host}' '${cfg.spaceDir}'";
        EnvironmentFile = config.sops.secrets.silverbullet-auth.path;
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };
  };
}
;
}
