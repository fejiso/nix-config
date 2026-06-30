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
        model = "opencode-go/deepseek-v4-pro";
        provider.openrouter.options.apiKey =
          "{file:${config.sops.secrets.openrouter-api-key.path}}";
        # Floor pricing for every OpenRouter model: route to the cheapest
        # provider. extraBody is merged into each request, so it applies
        # globally without naming models (the model picker has no :floor entry).
        provider.openrouter.options.extraBody.provider.sort = "price";
        provider.opencode-go.options.apiKey =
          "{file:${config.sops.secrets.opencodego-api-key.path}}";
        # z.ai GLM coding plan — OpenAI-compatible coding endpoint. Models come
        # from the built-in models.dev "zai" registry; we only override the
        # endpoint/key. Select a GLM model at runtime with /models.
        provider.zai.options = {
          baseURL = "https://api.z.ai/api/coding/paas/v4";
          apiKey = "{file:${config.sops.secrets.zai-api-key.path}}";
          # GLM-5.x are reasoning models; the coding endpoint defaults thinking
          # ON and streams `reasoning_content` before any text. When the model
          # goes reasoning -> tool_call with no intervening text content,
          # opencode's interleaved-reasoning parser stalls and the prompt hangs
          # forever. Disable server-side thinking to avoid that path entirely.
          extraBody.thinking.type = "disabled";
        };
        lsp = true;
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
