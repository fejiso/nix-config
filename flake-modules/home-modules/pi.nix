{ ... }: {
  flake.modules.homeManager.pi-agent =
# pi coding agent (earendil-works/pi) — terminal AI coding CLI, command `pi`.
# OpenRouter is a built-in provider; its key goes in ~/.pi/agent/auth.json,
# whose `key` field supports "!cmd" execution, so we reference the sops secret
# via "!cat <path>" — no key in the world-readable nix store, like opencode's
# {file:...}. Node-based (not a bun binary), so it runs on devdesktop too.
#
# z.ai's "ZAI Coding Plan (Global)" is a built-in provider (auth.json key
# `zai`), so it needs only an api_key entry — pi supplies its own model list,
# nothing is hardcoded. Like openrouter, the key is read at runtime via "!cat".
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi-agent;

  authConfig = (pkgs.formats.json { }).generate "pi-auth.json" {
    openrouter = {
      type = "api_key";
      key = "!cat ${config.sops.secrets.openrouter-api-key.path}";
    };
    zai = {
      type = "api_key";
      key = "!cat ${config.sops.secrets.zai-api-key.path}";
    };
  };

  configDir = "${config.home.homeDirectory}/.pi/agent";
in

{
  options.programs.pi-agent = {
    enable = lib.mkEnableOption "pi coding agent";
    # Set to null on hosts where the binary won't run, to keep config but skip
    # installing the package.
    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = pkgs.pi-coding-agent;
      defaultText = "pkgs.pi-coding-agent";
      description = "The pi coding agent package to install, or null for none.";
    };
    # When false (e.g. work machines), install the CLI but deploy no personal
    # OpenRouter auth — authenticate with work credentials instead.
    personalProviders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Write the personal OpenRouter auth for pi.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { home.packages = lib.mkIf (cfg.package != null) [ cfg.package ]; }

    # Personal OpenRouter auth — skipped on machines that opt out (the openrouter
    # sops secret isn't declared there, via opencode.nix). auth.json is written
    # as a real 0600 file (pi manages settings.json in the same dir).
    (lib.mkIf cfg.personalProviders {
      home.activation.piAgentAuth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${configDir}
        install -m 0600 ${authConfig} ${configDir}/auth.json
      '';
    })
  ]);
};
}
