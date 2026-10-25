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
        ${lib.optionalString (pkgs.stdenv.isDarwin || builtins.elem hostname [ "devdesktop" "gravidesktop" ]) ''
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
      bwrap-yolo = {
        description = "Run a command in a network-enabled bubblewrap sandbox with $HOME masked and only $PWD mounted RW";
        body = ''
          set -l workdir (pwd)
          set -l extra_binds
          set -l cmd_args

          set -l i 1
          set -l argc (count $argv)
          while test $i -le $argc
            set -l arg $argv[$i]
            switch $arg
              case --
                set i (math $i + 1)
                if test $i -le $argc
                  set -a cmd_args $argv[$i..-1]
                end
                break
              case --ro
                set i (math $i + 1)
                if test $i -gt $argc
                  echo "bwrap-yolo: --ro requires a path" >&2
                  return 1
                end
                set -l p (realpath -s -m -- $argv[$i])
                set -a extra_binds --ro-bind $p $p
              case '--ro=*'
                set -l p (realpath -s -m -- (string replace -r '^--ro=' "" -- $arg))
                set -a extra_binds --ro-bind $p $p
              case --rw
                set i (math $i + 1)
                if test $i -gt $argc
                  echo "bwrap-yolo: --rw requires a path" >&2
                  return 1
                end
                set -l p (realpath -s -m -- $argv[$i])
                set -a extra_binds --bind $p $p
              case '--rw=*'
                set -l p (realpath -s -m -- (string replace -r '^--rw=' "" -- $arg))
                set -a extra_binds --bind $p $p
              case '*'
                set -a cmd_args $argv[$i..-1]
                break
            end
            set i (math $i + 1)
          end

          if test (count $cmd_args) -eq 0
            echo "Usage: bwrap-yolo [--ro <dir>]... [--rw <dir>]... [--] <command> [args...]" >&2
            return 1
          end

          # Ensure agent config/state dirs exist on host before binding
          mkdir -p "$HOME/.kimi" "$HOME/.config/opencode" "$HOME/.local/share/opencode" "$HOME/.claude" "$HOME/.gemini"

          set -l bwrap_args \
            # 1. Isolate mount, PID, IPC, and UTS namespaces, but KEEP network shared
            --unshare-all \
            --share-net \
            --die-with-parent \
            # 2. Core virtual filesystems
            --proc /proc \
            --dev /dev \
            --tmpfs /tmp \
            --tmpfs /run \
            # 3. Read-only system binaries, libraries, and Nix store (if on NixOS)
            --ro-bind /usr /usr \
            --ro-bind-try /bin /bin \
            --ro-bind-try /lib /lib \
            --ro-bind-try /lib64 /lib64 \
            --ro-bind-try /nix /nix \
            --ro-bind-try /run/current-system /run/current-system \
            # 4. Network & TLS requirements (DNS + SSL certs + /etc/static for NixOS)
            --ro-bind /etc/resolv.conf /etc/resolv.conf \
            --ro-bind-try /etc/hosts /etc/hosts \
            --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf \
            --ro-bind-try /etc/ssl /etc/ssl \
            --ro-bind-try /etc/ca-certificates /etc/ca-certificates \
            --ro-bind-try /etc/pki /etc/pki \
            --ro-bind-try /etc/static /etc/static \
            --ro-bind-try /opt /opt \
            --ro-bind-try /etc/profiles /etc/profiles \
            # 5. Wipe $HOME with an empty tmpfs so ~/.ssh, ~/.aws, etc. are invisible
            --tmpfs "$HOME" \
            # 6. Selectively re-bind only agent auth/state & read-only gitconfig
            --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig" \
            --bind-try "$HOME/.kimi" "$HOME/.kimi" \
            --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode" \
            --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode" \
            --bind-try "$HOME/.claude" "$HOME/.claude" \
            --ro-bind-try "$HOME/.claude.json" "$HOME/.claude.json" \
            --ro-bind-try "$HOME/dev" "$HOME/dev" \
            --bind-try "$HOME/.gemini" "$HOME/.gemini" \
            # 7. Mount ONLY the current project directory as Read-Write (with .git/hooks & .git/config protected)
            --bind "$workdir" "$workdir" \
            --ro-bind-try "$workdir/.git/hooks" "$workdir/.git/hooks" \
            --ro-bind-try "$workdir/.git/config" "$workdir/.git/config" \
            # 8. Extra user-specified RO/RW mounts
            $extra_binds \
            --chdir "$workdir"

          command bwrap $bwrap_args -- $cmd_args
        '';
      };
      yolo-kimi = {
        description = "Run Kimi CLI in autonomous YOLO mode inside bwrap-yolo";
        body = ''
          set -l bwrap_flags
          set -l agent_args
          set -l i 1
          set -l argc (count $argv)
          while test $i -le $argc
            switch $argv[$i]
              case --ro --rw
                set -l flag $argv[$i]
                set i (math $i + 1)
                if test $i -le $argc
                  set -l p (realpath -s -m -- $argv[$i])
                  set -a bwrap_flags $flag $p
                  if test -d "$p"
                    set -a agent_args --add-dir $p
                  end
                end
              case '--ro=*' '--rw=*'
                set -a bwrap_flags $argv[$i]
                set -l p (realpath -s -m -- (string replace -r '^--r[ow]=' "" -- $argv[$i]))
                if test -d "$p"
                  set -a agent_args --add-dir $p
                end
              case '*'
                set -a agent_args $argv[$i]
            end
            set i (math $i + 1)
          end
          bwrap-yolo $bwrap_flags -- kimi --yolo $agent_args
        '';
      };
      yolo-claude = {
        description = "Run Claude Code in autonomous YOLO mode inside bwrap-yolo";
        body = ''
          set -l bwrap_flags
          set -l agent_args
          set -l i 1
          set -l argc (count $argv)
          while test $i -le $argc
            switch $argv[$i]
              case --ro --rw
                set -l flag $argv[$i]
                set i (math $i + 1)
                if test $i -le $argc
                  set -l p (realpath -s -m -- $argv[$i])
                  set -a bwrap_flags $flag $p
                  if test -d "$p"
                    set -a agent_args --add-dir $p
                  end
                end
              case '--ro=*' '--rw=*'
                set -a bwrap_flags $argv[$i]
                set -l p (realpath -s -m -- (string replace -r '^--r[ow]=' "" -- $argv[$i]))
                if test -d "$p"
                  set -a agent_args --add-dir $p
                end
              case '*'
                set -a agent_args $argv[$i]
            end
            set i (math $i + 1)
          end
          bwrap-yolo $bwrap_flags -- claude --dangerously-skip-permissions --settings '{"sandbox":{"enabled":false}}' $agent_args
        '';
      };
      yolo-agy = {
        description = "Run Antigravity CLI (agy) in autonomous YOLO mode inside bwrap-yolo";
        body = ''
          set -l bwrap_flags
          set -l agent_args
          set -l i 1
          set -l argc (count $argv)
          while test $i -le $argc
            switch $argv[$i]
              case --ro --rw
                set -l flag $argv[$i]
                set i (math $i + 1)
                if test $i -le $argc
                  set -l p (realpath -s -m -- $argv[$i])
                  set -a bwrap_flags $flag $p
                  if test -d "$p"
                    set -a agent_args --add-dir $p
                  end
                end
              case '--ro=*' '--rw=*'
                set -a bwrap_flags $argv[$i]
                set -l p (realpath -s -m -- (string replace -r '^--r[ow]=' "" -- $argv[$i]))
                if test -d "$p"
                  set -a agent_args --add-dir $p
                end
              case '*'
                set -a agent_args $argv[$i]
            end
            set i (math $i + 1)
          end
          bwrap-yolo $bwrap_flags -- agy --dangerously-skip-permissions $agent_args
        '';
      };
    };
  };
}
;
}
