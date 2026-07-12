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
#
# LazyPi (robzolkos/LazyPi) is an opinionated "distribution" of pi: it curates
# ~25 community pi packages (sub-agents, MCP, web access, memory, plan, diff
# review, powerbar, usage dashboard, themes, …) and writes them into
# ~/.pi/agent/settings.json so pi auto-installs them. We deploy that catalog
# *declaratively* (mirroring what `npx @robzolkos/lazypi --yes` would write)
# so the distribution is reproducible and active on first `pi` launch, with no
# network at home-manager activation time — pi fetches each package lazily on
# startup (it auto-installs any missing package from user/global settings, no
# project-trust prompt). The `lazypi` CLI ships too, for status/doctor/update.
{ config, lib, pkgs, ... }:

let
  cfg = config.programs.pi-agent;
  lazypiCfg = cfg.lazypi;

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

  # LazyPi v0.6.3 catalog — { id, source } pairs in category order
  # (core/ui/research/frameworks/themes), verbatim from bin/lazypi.mjs. `source`
  # is the exact string lazypi passes to `pi install` (and what pi writes to
  # settings.json's `packages` array). Pinned git refs are intentional. Keep
  # this in sync when bumping pkgs/lazypi.
  lazypiCatalog = [
    # core
    { id = "subagents"; source = "npm:pi-subagents"; }
    { id = "pi-ask-user"; source = "npm:pi-ask-user"; }
    { id = "mcp"; source = "npm:pi-mcp-adapter"; }
    { id = "web-access"; source = "npm:pi-web-access"; }
    { id = "memory"; source = "git:github.com/VandeeFeng/pi-memory-md"; }
    { id = "plan"; source = "npm:@devkade/pi-plan"; }
    { id = "simplify"; source = "npm:pi-simplify"; }
    { id = "add-dir"; source = "npm:pi-add-dir"; }
    { id = "prompt-templates"; source = "npm:pi-prompt-template-model"; }
    { id = "claude-cli"; source = "npm:pi-claude-cli"; }
    # ui
    { id = "plannotator"; source = "npm:@plannotator/pi-extension"; }
    { id = "slopchop"; source = "npm:pi-slopchop"; }
    { id = "extension-settings"; source = "npm:@juanibiapina/pi-extension-settings"; }
    { id = "powerbar"; source = "npm:@juanibiapina/pi-powerbar"; }
    { id = "usage"; source = "npm:@tmustier/pi-usage-extension"; }
    { id = "raw-paste"; source = "npm:@tmustier/pi-raw-paste"; }
    { id = "todos"; source = "git:github.com/tintinweb/pi-manage-todo-list@b75c449aa85ce328e9a8b632f62bf642aed40359"; }
    { id = "btw"; source = "npm:pi-btw"; }
    { id = "interactive-shell"; source = "npm:pi-interactive-shell"; }
    # research
    { id = "autoresearch"; source = "git:github.com/davebcn87/pi-autoresearch"; }
    { id = "ralph-wiggum"; source = "npm:@tmustier/pi-ralph-wiggum"; }
    # frameworks
    # compound (npm:@every-env/compound-plugin) is intentionally NOT here: it is
    # installed via a `bunx @every-env/compound-plugin install …` flow that
    # writes skills/agents/AGENTS.md into ~/.pi/agent — not a plain `pi install`
    # source, so it can't be declaratively added to packages. lazypi itself
    # skips it when bun is absent. Install it manually if wanted:
    #   bunx @every-env/compound-plugin@3.0.0 install compound-engineering --to pi --pi-home ~/.pi/agent
    # themes
    { id = "hackerman"; source = "git:github.com/javierportillo/pi-hackerman@63b0a3ef2c7b14985ffeb6cac44614ba59cd5693"; }
    { id = "curated-themes"; source = "npm:@victor-software-house/pi-curated-themes"; }
    { id = "terminal-theme"; source = "npm:pi-terminal-theme"; }
  ];

  # Packages selected for deployment: whole catalog minus the ids the host opts
  # out of (via lazypi.except, e.g. research loops on a work box).
  selectedPackages =
    builtins.filter (p: !(builtins.elem p.id lazypiCfg.except)) lazypiCatalog;

  # Order extension-settings first: lazypi enforces that pi-extension-settings
  # loads before pi-powerbar (powerbar needs its settings panel). Putting it at
  # the head of the packages array satisfies that.
  orderedPackages =
    let
      first = builtins.filter (p: p.id == "extension-settings") selectedPackages;
      rest = builtins.filter (p: p.id != "extension-settings") selectedPackages;
    in
    first ++ rest;

  packageSources = map (p: p.source) orderedPackages;
  selectedIds = map (p: p.id) selectedPackages;

  # lazypi blanks pi-subagents' built-in agents (context-builder, planner, …)
  # so they fall back to the active session model instead of a hardcoded one.
  # Only applied when subagents is in the selection.
  subagentOverrides = lib.optionalAttrs (builtins.elem "subagents" selectedIds) {
    subagents.agentOverrides = lib.genAttrs
      [ "context-builder" "planner" "researcher" "reviewer" "scout" "worker" ]
      (_: { model = ""; });
  };

  # settings.json: declarative catalog + default provider/model. Written as a
  # real 0600 file so pi can still mutate it at runtime between switches (it
  # manages settings.json in this dir); the catalog/provider/model are reset to
  # this declarative baseline on each `home-manager switch`.
  settings = {
    defaultProvider = "zai";
    defaultModel = "glm-5.2";
  } // subagentOverrides
  // (lib.optionalAttrs lazypiCfg.enable { packages = packageSources; });

  settingsConfig = (pkgs.formats.json { }).generate "pi-settings.json" settings;

  configDir = "${config.home.homeDirectory}/.pi/agent";

  # /zaiusage — a deterministic (no-model) slash command that fetches and
  # renders z.ai API usage/quota limits. The script reads the API key the same
  # way pi's `zai` auth entry does: $Z_AI_API_KEY first, then the sops-deployed
  # key file (path baked in at build time, so nothing secret lands in the nix
  # store). pi runs the script via a `script:` deterministic step with
  # `handoff: never`, so it shows a result card and makes no LLM call (zero
  # token cost). Replaces the opencode /usage command (opencode.nix), which
  # routed through the model and didn't reliably print verbatim.
  zaiKeyPath = config.sops.secrets.zai-api-key.path;

  zaiUsageScript = pkgs.writeTextFile {
    name = "zaiusage.sh";
    executable = true;
    text = ''
      #!/usr/bin/env bash
      set -uo pipefail

      KEY_FILE="''${Z_AI_KEY_FILE:-${zaiKeyPath}}"
      KEY="''${Z_AI_API_KEY:-}"
      if [ -z "$KEY" ] && [ -r "$KEY_FILE" ]; then
        KEY="$(cat "$KEY_FILE")"
      fi

      if [ -z "$KEY" ]; then
        echo "z.ai usage: no API key found." >&2
        echo "  Set \$Z_AI_API_KEY or make \$KEY_FILE readable." >&2
        exit 1
      fi

      if ! command -v jq >/dev/null 2>&1; then
        echo "z.ai usage: jq is required but not installed." >&2
        exit 1
      fi

      RESPONSE="$(curl -sS --max-time 12 'https://api.z.ai/api/monitor/usage/quota/limit' \
        -H "Authorization: Bearer $KEY" -H 'Accept: application/json' 2>/dev/null)"
      CURL_EXIT=$?

      if [ $CURL_EXIT -ne 0 ]; then
        echo "z.ai usage: request failed (curl exit $CURL_EXIT)." >&2
        exit 1
      fi

      if ! echo "$RESPONSE" | jq -e '.success == true' >/dev/null 2>&1; then
        echo "$RESPONSE" | jq -r '"z.ai usage: API reported failure — code \(.code // \"?\"), msg: \(.msg // \"unknown\")"' 2>/dev/null \
          || echo "z.ai usage: invalid JSON response."
        echo "--- raw response ---" >&2
        echo "$RESPONSE" >&2
        exit 1
      fi

      echo "$RESPONSE" | jq -r '
      def bar:
        ([.percentage/5|floor,0]|max) as $f | (20-$f) as $e |
        "\("█"*$f)\("░"*$e)  \(.percentage)%";
      def ulabel: {"3":"h","5":"mo","6":"d"}[.unit|tostring] // "u";
      "z.ai usage quota — plan: \(.data.level // "unknown")",
      "",
      (.data.limits[]? |
        if .type == "TOKENS_LIMIT" then
          "Tokens (\(.number // "?")\(ulabel)) window",
          "  \(bar)   resets \(.nextResetTime/1000|strftime("%Y-%m-%d %H:%M UTC"))",
          ""
        elif .type == "TIME_LIMIT" then
          "Monthly time quota",
          "  \(bar)   \(.remaining // 0)/\(.usage // 0) remaining   resets \(.nextResetTime/1000|strftime("%Y-%m-%d %H:%M UTC"))",
          "  per-model: \(.usageDetails | map("\(.modelCode) \(.usage)") | join(" · "))",
          ""
        else
          "\(.type)",
          "  \(bar)   resets \(.nextResetTime/1000|strftime("%Y-%m-%d %H:%M UTC"))",
          ""
        end)'
    '';
  };

  zaiUsagePrompt = pkgs.writeTextFile {
    name = "zaiusage.md";
    text = ''
      ---
      description: Show current z.ai API usage and quota limits
      script: ${zaiUsageScript}
      handoff: never
      timeout: 20000
      ---
    '';
  };
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

    lazypi = {
      # The LazyPi "distribution": deploy the curated catalog of pi packages
      # into ~/.pi/agent/settings.json. pi auto-installs any missing package on
      # startup, so the distribution is active on first launch with no network
      # at activation time. Disable to run a bare pi.
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Deploy the LazyPi curated package catalog for pi.";
      };
      package = lib.mkOption {
        type = lib.types.nullOr lib.types.package;
        default = pkgs.lazypi;
        defaultText = "pkgs.lazypi";
        description = "The lazypi CLI package to install, or null for none.";
      };
      except = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          LazyPi catalog package ids to exclude (e.g. "autoresearch",
          "ralph-wiggum"). See the lazypiCatalog list in this module for ids.
          Note: "compound" is always excluded (needs bun at install time).
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      home.packages =
        lib.optional (cfg.package != null) cfg.package
        ++ lib.optional (lazypiCfg.enable && lazypiCfg.package != null) lazypiCfg.package;
    }

    # Personal OpenRouter auth — skipped on machines that opt out (the openrouter
    # sops secret isn't declared there, via opencode.nix). auth.json is written
    # as a real 0600 file (pi manages settings.json in the same dir).
    (lib.mkIf cfg.personalProviders {
      home.file = {
        ".pi/agent/prompts/zaiusage.md".source = zaiUsagePrompt;
      };
      home.activation.piAgentAuth = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
        mkdir -p ${configDir}
        install -m 0600 ${authConfig} ${configDir}/auth.json
        install -m 0600 ${settingsConfig} ${configDir}/settings.json
      '';
    })
  ]);
};
}
