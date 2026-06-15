{ ... }: {
  flake.modules.homeManager.fish =
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
      direnv hook fish | source

      # Ensure DBUS and XDG variables are available (Linux only)
      if test (uname) = "Linux"
        if test -z "$DBUS_SESSION_BUS_ADDRESS"
          set -x DBUS_SESSION_BUS_ADDRESS "unix:path=$XDG_RUNTIME_DIR/bus"
        end
        if test -z "$XDG_RUNTIME_DIR"
          set -x XDG_RUNTIME_DIR "/run/user/"(id -u)
        end
      end

      set -gx GPG_TTY (tty)
      gpg-connect-agent updatestartuptty /bye >/dev/null
      bind \ct __fzf_open_file
      bind alt-backspace backward-kill-word

      set -Ux FZF_DEFAULT_OPTS '-m -s --ansi -x -e --inline-info --history-size=1000000'
      set -Ux FZF_DEFAULT_COMMAND "rg --files -g '!.git'"
      set SHELL (which fish)
      set HELIX_RUNTIME $HOME/dev/runtime

      # Clean up legacy universal variable to avoid persistence issues and root path pollution
      if set -q fish_user_paths
        set -l new_paths
        for path in $fish_user_paths
          if not string match -q "/root*" -- $path
            if test "$path" != "$HOME/.toolbox/bin"
              set -a new_paths $path
            end
          end
        end
        set -U fish_user_paths $new_paths
      end

      fish_add_path --path --append $HOME/.nix-profile/bin
      fish_add_path --path --append $HOME/.local/bin
      fish_add_path --path --append ~/.nix-profile/bin
      fish_add_path --path --append /opt/homebrew/opt/libpq/bin
      fish_add_path --path --append $HOME/.local/share/flatpak/exports/bin
      fish_add_path --path --append /var/lib/flatpak/exports/bin
      fish_add_path --path --prepend $HOME/.cargo/bin
      fish_add_path --path --prepend $HOME/bin
      
      if test "$USER" != "root"
        ${lib.optionalString (pkgs.stdenv.isDarwin || hostname == "devdesktop") ''
        fish_add_path --path --prepend $HOME/.toolbox/bin
        # On corp machines the nix bun binaries don't run, so opencode/kilo are
        # installed from upstream into these dirs — put them on PATH.
        fish_add_path --path --prepend $HOME/.opencode/bin
        fish_add_path --path --prepend $HOME/.kilo/bin''}
      end

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
;
}
