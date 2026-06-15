{ ... }: {
  flake.modules.homeManager.kilocode =
# Kilo Code CLI (the `kilo`/`kilocode` binary). At startup the CLI merges
# global config from ~/.config/kilo/{config.json,kilo.json,kilo.jsonc,...}.
# kilo is an opencode fork and supports {file:...} substitution, so the
# OpenRouter key is referenced from the sops secret rather than embedded.
#
# kilo.json is written as a real (writable) file rather than a home-manager
# store symlink: when kilo loads a config without a "$schema" key it rewrites
# the file in place to inject one (config.ts), which EACCES-fails on a 0444
# store symlink. We pre-set "$schema" so it won't rewrite, and keep the file
# writable so any future CLI-managed write succeeds too.
{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.programs.kilocode;
  jsonFormat = pkgs.formats.json { };

  kiloConfig = jsonFormat.generate "kilo.json" {
    "$schema" = "https://app.kilo.ai/config.json";
    model = "openrouter/anthropic/claude-sonnet-4-20250514";
    provider.openrouter.options.apiKey =
      "{file:${config.sops.secrets.openrouter-api-key.path}}";
  };

  configDir = "${config.home.homeDirectory}/.config/kilo";
in

{
  options.programs.kilocode = {
    enable = lib.mkEnableOption "Kilo Code CLI";
    # When false (e.g. work machines), install the CLI but deploy no personal
    # OpenRouter config — the user authenticates with work credentials instead.
    personalProviders = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Write the personal OpenRouter provider config for kilo.";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    { home.packages = [ pkgs.unstable.kilo ]; }

    # Personal OpenRouter config — skipped on machines that opt out (the
    # openrouter sops secret isn't even declared there, via opencode.nix).
    (lib.mkIf cfg.personalProviders {
      # Earlier generations linked the whole ~/.config/kilo dir (and later
      # kilo.json) to a read-only store path. Remove any such stale symlink so
      # the directory is real and writable for both our config and the CLI.
      home.activation.kiloConfig = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        if [[ -L "$HOME/.config/kilo" ]]; then
          rm "$HOME/.config/kilo"
        fi
        mkdir -p ${configDir}
        install -m 0644 ${kiloConfig} ${configDir}/kilo.json
      '';
    })
  ]);
};
}
