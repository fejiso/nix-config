# Work laptop (macOS) specific home-manager configuration
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
  ];

  # macOS specific configuration
  home = {
    username = "superfer";
    homeDirectory = "/Users/superfer";
  };

  # macOS specific packages
  home.packages = with pkgs; [
    # macOS development tools
    
    # Work-specific tools
    
    # macOS utilities
  ];

  # macOS specific shell configuration
  programs.zsh.initExtra = ''
    # macOS specific environment
    export HOMEBREW_PREFIX="/opt/homebrew"
    export HOMEBREW_CELLAR="/opt/homebrew/Cellar"
    export HOMEBREW_REPOSITORY="/opt/homebrew"
    export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
    export MANPATH="/opt/homebrew/share/man:$MANPATH"
    export INFOPATH="/opt/homebrew/share/info:$INFOPATH"
  '';

  # Git configuration for work
  programs.git = {
    userName = lib.mkForce "superfer";
    userEmail = lib.mkForce "superfer@amazon.com"; # Adjust as needed
  };

  # macOS specific programs
  programs.alacritty.settings.window.decorations = lib.mkForce "buttonless";

  # Configure atuin client to sync with devdesktop server
  programs.atuin.settings.sync_address = "http://superfer.aka.corp.amazon.com:8888";
}
