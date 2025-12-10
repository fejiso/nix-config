# Git configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  programs.git = {
    enable = true;
    
    settings = {
      init.defaultBranch = "main";
      push.default = lib.mkForce "simple";
      pull.rebase = true;
      core.editor = "vim";
      
      alias = {
        st = "status";
        co = "checkout";
        br = "branch";
        ci = "commit";
        unstage = "reset HEAD --";
        last = "log -1 HEAD";
        visual = "!gitk";
      };
    };
  };
  
}
