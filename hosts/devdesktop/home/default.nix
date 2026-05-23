# DevDesktop (Amazon Linux) specific home-manager configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  # Amazon Linux specific configuration
  home = {
    username = "superfer";
    homeDirectory = "/home/superfer";
  };

  # Amazon Linux specific packages
  home.packages = with pkgs; [
    # AWS-specific tools
    awscli2
    aws-vault
    aws-sam-cli
    
    # Development tools for Amazon Linux
    python3
    python3Packages.pip
    nodejs
    yarn
    
    # Amazon Linux utilities
    amazon-ecr-credential-helper
  ];

  # Enable atuin server
  services.atuin-server = {
    enable = true;
    openRegistration = true;  # Set to false after initial registration
  };

  # Configure atuin client to use local server
  programs.atuin.settings.sync_address = "http://localhost:8888";

  # Amazon Linux specific shell configuration
  programs.zsh.initExtra = ''
    # Amazon Linux specific environment
    export AWS_DEFAULT_REGION=us-east-1
    
    # Add local bin to PATH if it exists
    if [ -d "$HOME/.local/bin" ]; then
      export PATH="$HOME/.local/bin:$PATH"
    fi
  '';

  # Git configuration for work
  programs.git = {
    userName = lib.mkForce "superfer";
    userEmail = lib.mkForce "superfer@amazon.com"; # Adjust as needed
  };

}
