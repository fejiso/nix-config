# Heavy development tools module
{ config, lib, pkgs, ... }:

with lib;

{
  options.programs.dev-heavy = {
    enable = mkEnableOption "heavy development tools (VSCode, Haskell, Arduino, etc.)";
  };

  config = mkIf config.programs.dev-heavy.enable {
    home.packages = with pkgs; [
      # IDEs
      vscode
      kiro

      # Haskell development
      haskell-language-server

      # Arduino/embedded development
      arduino-ide
      arduino-cli

      # Other heavy dev tools
      stripe-cli
      jdt-language-server  # Java
    ];

    # Helix haskell language server config
    programs.helix.languages = {
      language-server.haskell-language-server = {
        command = "${pkgs.haskell-language-server}/bin/haskell-language-server-wrapper";
        args = ["--lsp"];
      };
      language = [
        {
          name = "haskell";
          auto-format = true;
          language-servers = ["haskell-language-server"];
          file-types = ["hs" "lhs" "tidal"];
        }
      ];
    };
  };
}
