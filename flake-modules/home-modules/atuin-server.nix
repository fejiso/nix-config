{ ... }: {
  flake.modules.homeManager.atuin-server =
# Atuin sync server module for home-manager
{ config, pkgs, lib, ... }:

with lib;

let
  cfg = config.services.atuin-server;
in {
  options.services.atuin-server = {
    enable = mkEnableOption "Atuin sync server";

    host = mkOption {
      type = types.str;
      default = "0.0.0.0";
      description = "The host address to bind to";
    };

    port = mkOption {
      type = types.port;
      default = 8888;
      description = "The port to listen on";
    };

    openRegistration = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to allow new user registrations";
    };
  };

  config = mkIf cfg.enable {
    home.packages = [ pkgs.atuin ];

    xdg.configFile."atuin/server.toml".text = ''
      host = "${cfg.host}"
      port = ${toString cfg.port}
      open_registration = ${boolToString cfg.openRegistration}
      db_uri = "sqlite://${config.xdg.dataHome}/atuin/server.db"
    '';

    systemd.user.services.atuin-server = {
      Unit = {
        Description = "Atuin sync server";
        After = [ "network.target" ];
      };
      Service = {
        ExecStart = "${pkgs.atuin}/bin/atuin server start";
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
