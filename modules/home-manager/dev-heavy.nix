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
      openjdk
      localsend
    ];

    # Helix editor configuration (heavy due to rust-analyzer, clangd pulling LLVM)
    programs.helix = {
      enable = true;
      settings = {
        theme = "gruvbox_dark_hard";
        editor = {
          true-color = true;
          line-number = "relative";
          mouse = true;
          cursor-shape = {
            insert = "bar";
            normal = "block";
            select = "underline";
          };
          file-picker = {
            hidden = false;
          };
          auto-save = true;
          auto-format = true;
          idle-timeout = 50;
        };
      };
      languages = {
        language-server.pylsp = {
          command = "${pkgs.python3Packages.python-lsp-server}/bin/pylsp";
        };
        language-server.rust-analyzer = {
          command = "${pkgs.rust-analyzer}/bin/rust-analyzer";
        };
        language-server.clangd = {
          command = "${pkgs.clang-tools}/bin/clangd";
        };
        language-server.haskell-language-server = {
          command = "${pkgs.haskell-language-server}/bin/haskell-language-server-wrapper";
          args = ["--lsp"];
        };

        language = [
          {
            name = "nix";
            auto-format = true;
            formatter.command = "${pkgs.alejandra}/bin/alejandra";
          }
          {
            name = "rust";
            auto-format = true;
            language-servers = ["rust-analyzer"];
          }
          {
            name = "python";
            auto-format = true;
            language-servers = ["pylsp"];
          }
          {
            name = "c";
            auto-format = true;
            language-servers = ["clangd"];
          }
          {
            name = "cpp";
            auto-format = true;
            language-servers = ["clangd"];
          }
          {
            name = "haskell";
            auto-format = true;
            language-servers = ["haskell-language-server"];
            file-types = ["hs" "lhs" "tidal"];
          }
        ];
      };
    };
  };
}
