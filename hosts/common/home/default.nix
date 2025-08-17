# Common home-manager configuration shared across all systems
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
    ./shell.nix
    ./git.nix
    ./development.nix
    ./terminal.nix
    ./tools.nix
    ./user-personal
    ./user-home
  ];

  # Don't set nixpkgs when using useGlobalPkgs
  # nixpkgs = {
  #   overlays = [
  #     outputs.overlays.additions
  #     outputs.overlays.modifications
  #     outputs.overlays.unstable-packages
  #   ];
  #   config = {
  #     allowUnfree = true;
  #   };
  # };

  # Set username and home directory for NixOS systems (z-247)
  home = {
    # Disable version check warning since we're using unstable home-manager with stable NixOS
    enableNixpkgsReleaseCheck = false;
  };

  # Common packages across all systems
  home.packages = with pkgs; [
    # System utilities
    htop
    tree
    wget
    curl
    unzip
    zip
    jq
    ripgrep
    fd
    bat
    eza
    zoxide
    broot
    
    # Terminal and shell tools
    zellij
    fish
    
    # Development tools
    git
    gh
    direnv

    # Text editors
    vim
    nano

    # Added imperatively installed packages
    git-filter-repo
    localsend
    nil
    nix
    nix-index
    nixd
    rmlint
    sops
    strawberry
    pinentry-gnome3
    pinentry-curses
  ];

  # Enable home-manager
  programs.home-manager.enable = true;

  # XDG configuration
  xdg.enable = true;

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "25.05";
}
