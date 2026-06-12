{ ... }: {
  flake.modules.homeManager.opencode =
# opencode TUI agent with OpenRouter as the model provider.
# The API key lives in secrets/openrouter.yaml; edit with:
#   sops secrets/openrouter.yaml
{ config, pkgs, inputs, ... }: {
  programs.opencode = {
    enable = true;
    # opencode moves fast; track unstable
    package = pkgs.unstable.opencode;
    settings = {
      model = "openrouter/anthropic/claude-sonnet-4.5";
      provider.openrouter.options.apiKey =
        "{file:${config.sops.secrets.openrouter-api-key.path}}";
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
};
}
