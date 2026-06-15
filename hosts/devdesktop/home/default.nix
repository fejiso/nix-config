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

  # Personal tools that don't exist or aren't needed on the work machine.
  programs.antigravity-cli.enable = false;

  # Personal OpenRouter/OpenCode Go credentials must not land on the work machine.
  # opencode-work module (imported in devdesktop.nix) handles the Bedrock config.
  programs.opencode.personalProviders = false;
  programs.kilocode.enable = false;

  # Use the Amazon-provisioned claude (~/.toolbox/bin/claude), not the nixpkgs
  # build. package = null keeps home-manager managing claude-code settings but
  # installs no binary, so it never shadows the toolbox one on PATH.
  programs.claude-code.package = null;

  # Enable atuin server
  services.atuin-server = {
    enable = true;
    openRegistration = true;  # Set to false after initial registration
  };

  # Configure atuin client to use local server
  programs.atuin.settings.sync_address = "http://localhost:8888";

  # Amazon Linux specific shell configuration
  programs.zsh.initContent = ''
    # Amazon Linux specific environment
    export AWS_DEFAULT_REGION=us-east-1

    # Add local bin to PATH if it exists
    if [ -d "$HOME/.local/bin" ]; then
      export PATH="$HOME/.local/bin:$PATH"
    fi
  '';

  # Git configuration for work
  programs.git.settings.user = {
    name = lib.mkForce "superfer";
    email = lib.mkForce "superfer@amazon.com"; # Adjust as needed
  };

}
