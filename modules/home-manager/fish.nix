{
  config,
  pkgs,
  lib,
  hostname ? "",
  ...
}:

{
  programs.fish = {
    enable = true;
    shellAbbrs = {
      bb = "brazil-build";
      bba = "brazil-build apollo-pkg";
      bre = "brazil-runtime-exec";
      brc = "brazil-recursive-cmd";
      bws = "brazil ws";
      bwsuse = "bws use --gitMode -p";
      bwscreate = "bws create -n";
      bbr = "brc brazil-build";
      bball = "brc --allPackages";
      bbb = "brc --allPackages brazil-build";
      bbra = "bbr apollo-pkg";
      idea = "env _JAVA_AWT_WM_NONREPARENTING=1 XDG_SESSION_TYPE=x11 intellij-idea-ultimate";
      zz = "zi";
      rgi = "rg -i";
      ec2-ssh = "/apollo/env/EC2SSHWrapper/bin/ec2-ssh";
      isengard = "/apollo/bin/env -e AmazonAwsCli isengard";
      aws = "/apollo/bin/env -e AmazonAwsCli aws";
      sshenv = "/apollo/env/envImprovement/bin/sshenv";

    };
    interactiveShellInit = ''
      if not set --query fish_private_mode
        history merge
      end
      zoxide init fish | source
      set -gx GPG_TTY (tty)
      gpg-connect-agent updatestartuptty /bye >/dev/null
      bind \ct __fzf_open_file
      bind alt-backspace backward-kill-word
      direnv hook fish | source

      set -Ux FZF_DEFAULT_OPTS '-m -s --ansi -x -e --inline-info --history-size=1000000'
      set -Ux FZF_DEFAULT_COMMAND "rg --files -g '!.git'"
      set SHELL (which fish)
      set HELIX_RUNTIME $HOME/dev/runtime
      set PATH $PATH /home/z-247/.nix-profile/bin
      set PATH $PATH /home/z-247/.local/bin
      set PATH $PATH /home/superfer/.local/bin
      set PATH $PATH ~/.nix-profile/bin
      set PATH $PATH /opt/homebrew/opt/libpq/bin
      set -Ua fish_user_paths $HOME/.local/share/flatpak/exports/bin
      set -Ua fish_user_paths /var/lib/flatpak/exports/bin
      set -U fish_user_paths $HOME/.cargo/bin $fish_user_paths
      set -U fish_user_paths $HOME/bin $fish_user_paths
      ${lib.optionalString (pkgs.stdenv.isDarwin || hostname == "devdesktop") "set -U fish_user_paths $HOME/.toolbox/bin $fish_user_paths"}
      export ANT_ARGS='-logger org.apache.tools.ant.listener.AnsiColorLogger'
    '';
    plugins = [
      { name = "zoxide"; src = pkgs.zoxide.src; }
    ];
    functions = {
      __fzf_open_file = {
        body = ''
          set file (fzf --height 40% --preview 'bat --style=numbers --color=always --line-range :500 {}' --query "$buffer" --select-1 --exit-0)
          if test -n "$file"
              commandline -i "$file"
          end
        '';
      };
      zz = {
        body = "zi";
      };
      fish_user_key_bindings = {
        body = ''
          bind \e. history-token-search-backward
          bind \ek history-token-search-backward
          bind \ej history-token-search-forward
        '';
      };
      mcurl = {
        body = "/usr/bin/curl $argv -L --cookie ~/.midway/cookie --cookie-jar ~/.midway/cookie";
      };
    };
  };
}
