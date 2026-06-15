{ ... }: {
  flake.modules.homeManager.kilocode =
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.kilocode;
  jsonFormat = pkgs.formats.json { };

  staticConfig = jsonFormat.generate "kilocode-cli-config" {
    version = "1.0.0";
    mode = "code";
    telemetry = false;
    provider = "openrouter";
    providers = [
      {
        id = "openrouter";
        provider = "openrouter";
        openRouterModelId = "anthropic/claude-sonnet-4-20250514";
        openRouterUseMiddleOutTransform = true;
      }
    ];
  };

  configDir = "${config.home.homeDirectory}/.kilocode/cli";
in

{
  options.programs.kilocode.enable = lib.mkEnableOption "Kilo Code CLI";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.unstable.kilo ];

    home.activation.kilocodeConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      OPENROUTER_KEY=$(cat ${config.sops.secrets.openrouter-api-key.path} 2>/dev/null || echo "")
      mkdir -p ${configDir}
      ${lib.getExe pkgs.jq} --arg key "$OPENROUTER_KEY" \
        '.providers[0].openRouterApiKey = $key' \
        ${staticConfig} > ${configDir}/config.json
    '';
  };
};
}
