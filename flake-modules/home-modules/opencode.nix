{ ... }: {
  flake.modules.homeManager.opencode =
# opencode TUI agent with OpenRouter as the model provider.
# The API key lives in secrets/openrouter.yaml; edit with:
#   sops secrets/openrouter.yaml
# The OpenCode Go API key lives in secrets/opencodego.yaml; edit with:
#   sops secrets/opencodego.yaml
{ config, pkgs, inputs, ... }: {
  programs.opencode = {
    enable = true;
    # opencode moves fast; track unstable
    package = pkgs.unstable.opencode;
    settings = {
      model = "opencodego/deepseek-v4-pro";
      provider.openrouter.options.apiKey =
        "{file:${config.sops.secrets.openrouter-api-key.path}}";
      provider.opencodego = {
        npm = "@ai-sdk/openai-compatible";
        name = "OpenCode Go";
        options = {
          baseURL = "https://opencode.ai/zen/go/v1";
          apiKey = "{file:${config.sops.secrets.opencodego-api-key.path}}";
        };
      };
      # enable the built-in LSP servers (off by default)
      lsp = true;
    };
    tui.keybinds = {
      # default is ctrl+p, which clashes elsewhere
      command_list = "ctrl+i";
    };
  };

  sops.secrets.openrouter-api-key = {
    sopsFile = "${inputs.self}/secrets/openrouter.yaml";
    key = "openrouter_api_key";
    path = "${config.home.homeDirectory}/.local/share/opencode/openrouter-api-key";
    mode = "0600";
  };

  sops.secrets.opencodego-api-key = {
    sopsFile = "${inputs.self}/secrets/opencodego.yaml";
    key = "opencodego_api_key";
    path = "${config.home.homeDirectory}/.local/share/opencode/opencodego-api-key";
    mode = "0600";
  };
};
}
