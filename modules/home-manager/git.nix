{ config, pkgs, ... }:

{
  programs.git = {
    enable = true;
    userName = "Fernando Jiménez";
    userEmail = "fer@fer.xyz";
    aliases = {
      st = "status";
      ci = "commit";
      br = "branch";
      co = "checkout";
      df = "diff";
      lg = "log -p";
      l1 = "log --graph --decorate --pretty=oneline --abbrev-commit";
      l2 = "log --graph --decorate --pretty=short --abbrev-commit";
      l3 = "log --graph --decorate --pretty=medium --abbrev-commit";
      l4 = "log --graph --decorate --pretty=fuller --abbrev-commit";
      la1 = "log --graph --decorate --pretty=oneline --abbrev-commit --all";
      la2 = "log --graph --decorate --pretty=short --abbrev-commit --all";
      la3 = "log --graph --decorate --pretty=medium --abbrev-commit --all";
      la4 = "log --graph --decorate --pretty=fuller --abbrev-commit --all";
      ll = "log --graph --pretty=format:'%C(yellow)%d%Creset %C(cyan)%h%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit --date=short --all";
      ls = "ls-files";
      noffmg = "merge --no-ff";
      mg = "merge --no-ff";
      rmc = "rm -r --cached";
      
    };
    extraConfig = {
      color = {
        ui = true;
        branch = {
          current = "yellow reverse";
          local = "yellow";
          remote = "green";
        };
        diff = {
          meta = 11;
          frag = "magenta bold";
          old = "red bold";
          new = "green bold";
          whitespace = "red reverse";
          func = "146 bold";
          commit = "yellow bold";
        };
        status = {
          added = "yellow";
          changed = "green";
          untracked = "cyan";
        };
        diff-highlight = {
          oldNormal = "red bold";
          oldHighlight = "red bold 52";
          newNormal = "green bold";
          newHighlight = "green bold 22";
        };
      };
      core = {
        whitespace = "fix,-indent-with-non-tab,trailing-space,cr-at-eol";
      };
      push = {
        default = "tracking";
      };
      merge = {
        tool = "vimdiff";
      };
      credential = {
        helper = "store";
      };
      interactive = {
        #diffFilter = "diff-so-fancy --patch";
      };
      trailer = {
        changeid = {
          key = "Change-Id";
        };
      };
      filter = {
        lfs = {
          smudge = "git-lfs smudge -- %f";
          process = "git-lfs filter-process";
          required = true;
          clean = "git-lfs clean -- %f";
        };
      };
    };
  };
}