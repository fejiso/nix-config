# Tool configurations
{
  config,
  lib,
  pkgs,
  ...
}: {
  # Helix editor configuration
  # programs.helix = {
  #   enable = true;
  #   settings = {
  #     theme = "gruvbox_dark_hard";
  #     editor = {
  #       true-color = true;
  #       line-number = "relative";
  #       mouse = true;
  #       cursor-shape = {
  #         insert = "bar";
  #         normal = "block";
  #         select = "underline";
  #       };
  #       file-picker = {
  #         hidden = false;
  #       };
  #       auto-save = true;
  #       auto-format = true;
  #       idle-timeout = 50;
  #     };
  #     keys.normal = {
  #       space.space = "file_picker";
  #       space.w = ":w";
  #       space.q = ":q";
  #       esc = ["collapse_selection" "keep_primary_selection"];
  #     };
  #   };
  #   languages = {
  #     language = [
  #       {
  #         name = "nix";
  #         auto-format = true;
  #         formatter.command = "${pkgs.alejandra}/bin/alejandra";
  #       }
  #       {
  #         name = "rust";
  #         auto-format = true;
  #       }
  #       {
  #         name = "python";
  #         auto-format = true;
  #       }
  #     ];
  #   };
  # };

  # Bat configuration
  programs.bat = {
    enable = true;
    config = {
      theme = "TwoDark";
      pager = "less -FR";
    };
  };



  # Broot configuration
  programs.broot = {
    enable = true;
    settings = {
      modal = true;
      verbs = [
        {
          invocation = "edit";
          shortcut = "e";
          execution = "$EDITOR +{line} {file}";
          leave_broot = false;
        }
        {
          invocation = "create {subpath}";
          execution = "$EDITOR {directory}/{subpath}";
          leave_broot = false;
        }
        {
          invocation = "git_diff";
          shortcut = "gd";
          execution = "git diff {file}";
        }
      ];
    };
  };

  # Ripgrep configuration
  home.file.".ripgreprc".text = ''
    --max-columns=150
    --max-columns-preview
    --smart-case
    --hidden
    --no-ignore
    --no-ignore-vcs
    --follow
    --glob=!.git/*
    --glob=!node_modules/*
    --glob=!target/*
    --glob=!.direnv/*
    --glob=!build/*
    --glob=!z-env/*
    --glob=!__pycache__/*
    --glob=!*.pyc
    --glob=!env/*
  '';

  # Set RIPGREP_CONFIG_PATH
  home.sessionVariables = {
    RIPGREP_CONFIG_PATH = "${config.home.homeDirectory}/.ripgreprc";
  };
}
