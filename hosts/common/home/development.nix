# Development tools configuration
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}: {
  home.packages = with pkgs; [
    # Programming languages
    python3
    python3Packages.pip
    uv  # Fast Python package installer and resolver
    nodejs
    go
    rustc
    cargo
    # Development tools
    jetbrains.idea
    postman

    # Language servers (heavy ones in dev-heavy module)
    python3Packages.python-lsp-server
    clang-tools  # includes clangd for C/C++
    rust-analyzer

    # AWS tools
  ];

  # Direnv for environment management
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
  
  # Neovim configuration with LazyVim
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
    
    extraPackages = with pkgs; [
      # LazyVim dependencies
      git
      ripgrep
      fd
      nodejs
      inputs.nixpkgs-master.legacyPackages.${pkgs.system}.tree-sitter

      # Language servers (already in development tools but explicit here)
      lua-language-server
      nil # Nix LSP

      # Debug adapters for nvim-dap
      vscode-extensions.ms-python.debugpy  # Python debugger
    ];
    
    initLua = ''
      -- Bootstrap lazy.nvim
      local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
      if not vim.loop.fs_stat(lazypath) then
        vim.fn.system({
          "git",
          "clone",
          "--filter=blob:none",
          "https://github.com/folke/lazy.nvim.git",
          "--branch=stable",
          lazypath,
        })
      end
      vim.opt.rtp:prepend(lazypath)
      
      -- LazyVim setup
      require("lazy").setup({
        spec = {
          { "LazyVim/LazyVim", import = "lazyvim.plugins" },
          -- Enable DAP (Debug Adapter Protocol)
          { import = "lazyvim.plugins.extras.dap.core" },
          -- Enable Neotest for running tests
          { import = "lazyvim.plugins.extras.test.core" },
          {
            "nvim-treesitter/nvim-treesitter",
            branch = "main",
          },
          { "nvim-orgmode/orgmode",
            event = "VeryLazy",
            ft = { "org" },
            config = function()
              require("orgmode").setup({
                org_agenda_files = "~/Syncthing/Orgzly/**/*",
                org_default_notes_file = "~/Syncthing/Orgzly/refile.org",
              })
            end,
          },
          { "thgrund/tidal.nvim",
            -- Load eagerly to ensure autocmds are set up before BufEnter fires
            lazy = false,
            config = function()
              require("tidal").setup({
                boot = {
                  tidal = {
                    cmd = "${config.home.homeDirectory}/.local/bin/tidal/ghci",
                    args = {},
                    file = "${config.home.homeDirectory}/.tidal/BootTidal.hs",
                    enabled = true,
                  },
                  sclang = {
                    cmd = "sclang",
                    args = {},
                    file = nil,
                    enabled = false,
                  },
                  split = "v",
                },
                mappings = {
                  send_line = { mode = { "i", "n" }, key = "<S-CR>" },
                  send_visual = { mode = { "x" }, key = "<S-CR>" },
                  send_block = { mode = { "i", "n", "x" }, key = "<M-CR>" },
                  send_node = { mode = "n", key = "<leader><CR>" },
                  send_silence = { mode = "n", key = "<leader>d" },
                  send_hush = { mode = "n", key = "<leader><Esc>" },
                },
              })

              -- Drain stdout/stderr on start to prevent GHCi pipe deadlock.
              -- tidal.nvim defers attaching pipe readers until :TidalNotification,
              -- so without this, the OS pipe buffer fills and GHCi blocks on write.
              local Repl = require("tidal.util.repl.repl")
              local _orig_start = Repl.start
              function Repl:start(opts)
                local result = _orig_start(self, opts)
                if self.proc then
                  if self.stdout then self.stdout:read_start(function() end) end
                  if self.stderr then self.stderr:read_start(function() end) end
                end
                return result
              end
            end,
          },
        },
        defaults = {
          lazy = false,
          version = false,
        },
        checker = { enabled = true },
        performance = {
          rtp = {
            disabled_plugins = {
              "gzip",
              "tarPlugin",
              "tohtml",
              "tutor",
              "zipPlugin",
            },
          },
        },
      })
      
      -- Set up file association for .tidal files
      vim.filetype.add({
        extension = {
          tidal = "haskell",
        },
      })
    '';
  };
  
}
