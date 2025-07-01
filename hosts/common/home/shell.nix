# Shell configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  

  # Fish shell configuration
  programs.fish = {
    enable = true;
    interactiveShellInit = ''
      # Initialize zoxide
      zoxide init fish | source
      
      # Set up direnv
      direnv hook fish | source
    '';
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      ls = "eza";
      cat = "bat";
      grep = "rg";
      find = "fd";
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
      find = "fd";
      cd = "z";  # Use zoxide for cd
    };
    
    history = {
      size = 10000;
      path = "${config.xdg.dataHome}/zsh/history";
    };
    
    oh-my-zsh = {
      enable = true;
      plugins = ["git" "sudo" "docker" "kubectl"];
      theme = "robbyrussell";
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
      find = "fd";
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
  
  # Starship prompt
  programs.starship = {
    enable = true;
    settings = {
      add_newline = false;
      character = {
        success_symbol = "[➜](bold green)";
        error_symbol = "[➜](bold red)";
      };
    };
  };
}
