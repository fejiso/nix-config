# Shell configuration
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Compute hostname color at build time
  hostnameColor =
    let
      hostname = config.networking.hostName or "unknown";
      # Hash hostname to get a consistent number
      hash = builtins.hashString "md5" hostname;
      # Convert first 8 chars of hash to number
      hashNum = lib.mod (lib.toInt ("0x" + builtins.substring 0 8 hash)) 16;
      # Color palette - 16 distinct colors
      colors = [
        "bold red"
        "bold green"
        "bold yellow"
        "bold blue"
        "bold purple"
        "bold cyan"
        "bold bright-red"
        "bold bright-green"
        "bold bright-yellow"
        "bold bright-blue"
        "bold bright-purple"
        "bold bright-cyan"
        "bold 208"  # orange
        "bold 165"  # magenta
        "bold 51"   # sky blue
        "bold 226"  # yellow
      ];
    in
      builtins.elemAt colors hashNum;
in {
  

  # Fish shell configuration
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Initialize zoxide
      zoxide init fish | source
      
      # Set up direnv
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
    '';
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      ls = "eza";
      cat = "bat";
      grep = "rg";
      cd = "z";  # Use zoxide for cd
    };
  };

  # Zsh configuration (keeping as backup)
  programs.zsh = {
    enable = true;
    enableCompletion = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;
    
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      ls = "eza";
      cat = "bat";
      grep = "rg";
      cd = "z";  # Use zoxide for cd
    };
    
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = ["git" "sudo" "docker" "kubectl"];
    };
    
    initContent = ''
      # Initialize zoxide
      eval "$(zoxide init zsh)"
      
      # Set up direnv
      eval "$(direnv hook zsh)"
    '';
  };
  
  # Bash configuration (fallback)
  programs.bash = {
    enable = true;
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      ls = "eza";
      cat = "bat";
      grep = "rg";
      cd = "z";  # Use zoxide for cd
    };
    initExtra = ''
      # Initialize zoxide
      eval "$(zoxide init bash)"
      
      # Set up direnv
      eval "$(direnv hook bash)"
    '';
  };
  
  # Zoxide configuration
  programs.zoxide = {
    enable = true;
  };
  
  # Direnv configuration
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };
  programs.claude-code = {
  	enable = true;
  };
  
  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;

      format = lib.concatStrings [
        "$os"
        "$username"
        "$hostname"
        "$directory"
        "$git_branch"
        "$git_commit"
        "$git_state"
        "$git_status"
        "$git_metrics"
        "$c"
        "$cmake"
        "$haskell"
        "$erlang"
        "$zig"
        "$nix_shell"
        "$python"
        "$nodejs"
        "$rust"
        "$golang"
        "$java"
        "$docker_context"
        "$kubernetes"
        "$terraform"
        "$aws"
        "$memory_usage"
        "$cmd_duration"
        "$line_break"
        "$jobs"
        "$battery"
        "$time"
        "$status"
        "$character"
      ];

      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[✗](bold red)";
        vicmd_symbol = "[V](bold green)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
        format = "[$path]($style)[$read_only]($read_only_style) ";
        style = "bold cyan";
        read_only = " ";
        read_only_style = "red";
      };

      git_branch = {
        format = "on [$symbol$branch(:$remote_branch)]($style) ";
        symbol = " ";
        style = "bold purple";
      };

      git_commit = {
        commit_hash_length = 7;
        format = "[\($hash$tag\)]($style) ";
        style = "bold green";
        only_detached = false;
        tag_disabled = false;
        tag_symbol = " 🏷 ";
      };

      git_status = {
        format = "([$all_status$ahead_behind]($style) )";
        conflicted = "=";
        ahead = "⇡\${count}";
        behind = "⇣\${count}";
        diverged = "⇕⇡\${ahead_count}⇣\${behind_count}";
        untracked = "?\${count}";
        stashed = "$";
        modified = "!\${count}";
        staged = "+\${count}";
        renamed = "»\${count}";
        deleted = "✘\${count}";
        style = "bold red";
      };

      git_state = {
        format = "[\($state( $progress_current of $progress_total)\)]($style) ";
        style = "bright-black";
      };

      git_metrics = {
        disabled = false;
        added_style = "bold green";
        deleted_style = "bold red";
        format = "[+$added]($added_style)/[-$deleted]($deleted_style) ";
      };

      cmd_duration = {
        min_time = 500;
        format = "took [$duration]($style) ";
        style = "bold yellow";
      };

      nix_shell = {
        disabled = false;
        impure_msg = "[impure](bold red)";
        pure_msg = "[pure](bold green)";
        format = "via [$symbol$state( \($name\))]($style) ";
        symbol = " ";
        style = "bold blue";
      };

      python = {
        format = "via [\${symbol}\${pyenv_prefix}(\${version} )(\($virtualenv\) )]($style)";
        symbol = " ";
        style = "yellow bold";
      };

      nodejs = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold green";
      };

      rust = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold red";
      };

      golang = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold cyan";
      };

      java = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold red";
      };

      c = {
        format = "via [$symbol($version(-$name) )]($style)";
        symbol = " ";
        style = "bold blue";
        detect_extensions = ["c" "h"];
      };

      cmake = {
        format = "via [$symbol($version )]($style)";
        symbol = "△ ";
        style = "bold blue";
      };

      haskell = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold purple";
      };

      erlang = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold red";
      };

      zig = {
        format = "via [$symbol($version )]($style)";
        symbol = " ";
        style = "bold yellow";
      };

      docker_context = {
        format = "via [$symbol$context]($style) ";
        symbol = " ";
        style = "bold blue";
      };

      kubernetes = {
        format = "on [$symbol$context( \($namespace\))]($style) ";
        symbol = "☸ ";
        style = "bold blue";
        disabled = false;
      };

      terraform = {
        format = "via [$symbol$workspace]($style) ";
        symbol = "💠 ";
        style = "bold purple";
      };

      aws = {
        format = "on [$symbol($profile )(\($region\) )]($style)";
        symbol = "☁️  ";
        style = "bold yellow";
      };

      battery = {
        full_symbol = "🔋";
        charging_symbol = "⚡";
        discharging_symbol = "💀";
        display = [
          {
            threshold = 15;
            style = "bold red";
          }
          {
            threshold = 50;
            style = "bold yellow";
          }
        ];
      };

      time = {
        disabled = false;
        format = "at [$time]($style) ";
        style = "bold white";
        time_format = "%T";
      };

      status = {
        disabled = false;
        format = "[$symbol$status]($style) ";
        symbol = "✖";
        style = "bold red";
      };

      jobs = {
        symbol = "+";
        number_threshold = 1;
        symbol_threshold = 1;
      };

      username = {
        format = "[$user]($style)@";
        style_user = "bold blue";
        show_always = false;
      };

      hostname = {
        format = "[$hostname]($style) in ";
        style = hostnameColor;
        ssh_only = false;
      };

      os = {
        disabled = false;
        format = "[$symbol]($style) ";
        style = "bold white";
        symbols = {
          Alpine = " ";
          Amazon = " ";
          Android = " ";
          Arch = " ";
          CentOS = " ";
          Debian = " ";
          Fedora = " ";
          FreeBSD = " ";
          Gentoo = " ";
          Linux = " ";
          Macos = " ";
          Manjaro = " ";
          NixOS = " ";
          OpenBSD = " ";
          openSUSE = " ";
          Raspbian = " ";
          Redhat = " ";
          RedHatEnterprise = " ";
          Ubuntu = " ";
          Unknown = " ";
          Windows = " ";
        };
      };

      memory_usage = {
        disabled = false;
        threshold = 75;
        format = "via $symbol[$ram( | $swap)]($style) ";
        symbol = " ";
        style = "bold dimmed white";
      };
    };
  };
}
