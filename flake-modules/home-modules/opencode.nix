{ ... }: {
  flake.modules.homeManager.opencode =
# opencode TUI agent with OpenRouter as the model provider.
# The API key lives in secrets/openrouter.yaml; edit with:
#   sops secrets/openrouter.yaml
# The OpenCode Go API key lives in secrets/opencodego.yaml; edit with:
#   sops secrets/opencodego.yaml
# The z.ai (GLM coding plan) API key lives in secrets/zai.yaml; edit with:
#   sops secrets/zai.yaml
{ config, lib, pkgs, inputs, ... }: {
  # personalProviders controls OpenRouter/OpenCode Go secret deployment.
  # Set to false on work machines that use a different AI backend.
  options.programs.opencode.personalProviders = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = "Deploy OpenRouter and OpenCode Go API keys via sops.";
  };

  config = lib.mkMerge [
    {
      programs.opencode = {
        enable = lib.mkDefault true;
        # opencode moves fast; track unstable. mkDefault so hosts where the
        # nix bun binary won't run (e.g. devdesktop) can set package = null and
        # install opencode from upstream while keeping nix-managed config.
        package = lib.mkDefault pkgs.unstable.opencode;
        tui.keybinds = {
          # default is ctrl+p, which clashes elsewhere
          command_list = "ctrl+i";
        };
      };
    }
    # Personal provider settings and secrets — skipped on work machines.
    (lib.mkIf config.programs.opencode.personalProviders {
      programs.opencode.settings = {
        model = "zai-coding-plan/glm-5.2";
        provider.openrouter.options.apiKey =
          "{file:${config.sops.secrets.openrouter-api-key.path}}";
        # Floor pricing for every OpenRouter model: route to the cheapest
        # provider. extraBody is merged into each request, so it applies
        # globally without naming models (the model picker has no :floor entry).
        provider.openrouter.options.extraBody.provider.sort = "price";
        provider.opencode-go.options.apiKey =
          "{file:${config.sops.secrets.opencodego-api-key.path}}";
        # z.ai GLM Coding Plan via the BUILT-IN `zai-coding-plan` provider
        # (auto-discovered from models.dev). We previously hand-rolled a custom
        # `provider.zai` that forced @ai-sdk/anthropic against
        # `api.z.ai/api/anthropic`, but that path hangs in opencode 1.17.9 (the
        # stream starts and then no chunks ever arrive — see opencode issues
        # #34126 / #34698 for the pending parser fix, and #31133 / #34672 for the
        # z.ai-specific transient network/retry bugs). The maintained
        # models.dev `zai-coding-plan` provider uses @ai-sdk/openai-compatible
        # against `api.z.ai/api/coding/paas/v4` and tracks the GLM streaming
        # quirks, so we lean on it instead of overriding npm/baseURL/models.
        # Only the API key needs supplying; pick another GLM with /models.
        provider."zai-coding-plan".options.apiKey =
          "{file:${config.sops.secrets.zai-api-key.path}}";
        lsp = true;
        # /usage — show the z.ai (GLM coding plan) API usage limits. The key is
        # read at runtime from the sops path so nothing secret lands in the
        # (world-readable) nix store; the command body just hands the agent a
        # curl|jq pipeline to run and print verbatim.
        command.usage = {
          description = "Show z.ai API usage limits and quota.";
          template = ''
            Run this bash command and print its stdout verbatim, with no commentary:

            ```bash
            KEY="$(cat ${config.sops.secrets.zai-api-key.path})"
            curl -sS 'https://api.z.ai/api/monitor/usage/quota/limit' \
              -H "Authorization: Bearer $KEY" | jq -r '
            "z.ai usage quota — plan level: \(.data.level)","",
            (.data.limits[] |
              "• \(.type): \(.percentage)% used",
              (if .remaining != null then "    remaining: \(.remaining) / \(.usage)" else empty end),
              "    resets: \(.nextResetTime/1000|strftime("%Y-%m-%d %H:%M UTC"))",
              "")'
            ```
          '';
        };
      };
      sops.secrets = {
        openrouter-api-key = {
          sopsFile = "${inputs.self}/secrets/openrouter.yaml";
          key = "openrouter_api_key";
          path = "${config.home.homeDirectory}/.local/share/opencode/openrouter-api-key";
          mode = "0600";
        };
        opencodego-api-key = {
          sopsFile = "${inputs.self}/secrets/opencodego.yaml";
          key = "opencodego_api_key";
          path = "${config.home.homeDirectory}/.local/share/opencode/opencodego-api-key";
          mode = "0600";
        };
        zai-api-key = {
          sopsFile = "${inputs.self}/secrets/zai.yaml";
          key = "zai_api_key";
          path = "${config.home.homeDirectory}/.local/share/opencode/zai-api-key";
          mode = "0600";
        };
      };
    })
  ];
};
}
