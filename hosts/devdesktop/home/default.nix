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
  imports = [
    ../../common/home-standalone
  ];

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

  # Disable systemd services (not available on Amazon Linux)
  systemd.user.startServices = lib.mkForce false;
  
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

  # Disable atuin
  programs.atuin.enable = lib.mkForce false;
}
