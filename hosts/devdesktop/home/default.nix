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

  # The nix bun-compiled opencode/kilo binaries segfault in the glibc loader on
  # this corp kernel (amzn2int KVM guest) — their unusual ELF layout trips it,
  # while ordinary nix binaries run fine. So install both from upstream here,
  # like the toolbox claude:
  #   opencode: curl -fsSL https://opencode.ai/install | bash
  #   kilo:     npm i -g @kilocode/cli   (or: bun install -g @kilocode/cli)
  #
  # opencode: the upstream home-manager module errors on package = null
  # (versionAtLeast on a null version), so disable the nix module outright and
  # configure the upstream binary directly when the work Bedrock details exist.
  programs.opencode.enable = lib.mkForce false;
  programs.opencode.personalProviders = false;

  # kilo: keep the module enabled but install no nix binary and deploy no
  # personal OpenRouter config — the upstream CLI uses work credentials.
  programs.kilocode.package = null;
  programs.kilocode.personalProviders = false;

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
