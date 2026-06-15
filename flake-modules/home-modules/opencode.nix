{ ... }: {
  flake.modules.homeManager.opencode =
# opencode TUI agent with OpenRouter as the model provider.
# The API key lives in secrets/openrouter.yaml; edit with:
#   sops secrets/openrouter.yaml
# The OpenCode Go API key lives in secrets/opencodego.yaml; edit with:
#   sops secrets/opencodego.yaml
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
        provider.opencode-go.options.apiKey =
          "{file:${config.sops.secrets.opencodego-api-key.path}}";
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
      };
    })
  ];
};
}
