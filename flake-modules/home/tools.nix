{ ... }: {
  flake.modules.homeManager.default =
# Tool configurations
{
  config,
  lib,
  pkgs,
  ...
}: {
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
;
}
