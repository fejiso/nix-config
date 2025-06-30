# Development tools configuration
{
  config,
  lib,
  pkgs,
  ...
}: {
  home.packages = with pkgs; [
    # Programming languages
    python3
    nodejs
    go
    rustc
    cargo
    
    # Development tools
    docker
    docker-compose
    kubectl
    terraform
    ansible
    
    # AWS tools
    awscli2
    aws-vault
    
    # Text editors and IDEs
    vscode
  ];
  
  # Direnv for environment management
  programs.direnv = {
    enable = true;
    enableZshIntegration = true;
    enableBashIntegration = true;
    nix-direnv.enable = true;
  };
  
  # Neovim configuration
  programs.neovim = {
    enable = true;
    defaultEditor = true;
    viAlias = true;
    vimAlias = true;
  };
}
