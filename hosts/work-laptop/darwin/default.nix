# Work laptop (macOS) Darwin configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  # macOS system configuration
  system.stateVersion = 4;
  system.primaryUser = "superfer";

  nixpkgs.config.allowUnfree = true;
  # Stable base with pkgs.unstable available for explicit package exceptions.
  # Corp network sinkholes proxy.golang.org; force Go vendor fetches
  # through GOPROXY=direct. See overlays/default.nix.
  nixpkgs.overlays = [
    outputs.overlays.additions
    outputs.overlays.modifications
    outputs.overlays.unstable-packages
    outputs.overlays.go-proxy-direct
  ];

  # Determinate Nix manages the daemon and nix.conf on this machine; disable
  # nix-darwin's native Nix management so they don't conflict.
  nix.enable = false;

  # macOS system preferences
  system.defaults = {
    dock = {
      autohide = true;
      orientation = "bottom";
      showhidden = true;
      mineffect = "genie";
    };
    
    finder = {
      AppleShowAllExtensions = true;
      ShowPathbar = true;
      ShowStatusBar = true;
    };
    
    NSGlobalDomain = {
      AppleShowAllExtensions = true;
      InitialKeyRepeat = 14;
      KeyRepeat = 1;
    };
  };

  # Homebrew integration
  homebrew = {
    enable = true;
    brews = [
      "mas" # Mac App Store CLI
    ];
    casks = [
      "docker"
      "visual-studio-code"
      "slack"
      "zoom"
      "1password"
    ];
    masApps = {
      "Xcode" = 497799835;
    };
  };

  # Fonts (nix-darwin manages /Library/Fonts/Nix Fonts directly)
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
  ];

  # User configuration
  users.users.superfer = {
    name = "superfer";
    home = "/Users/superfer";
  };
}
