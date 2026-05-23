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

  # Nix configuration
  nix = {
    settings = {
      experimental-features = "nix-command flakes";
    };
    optimise.automatic = true;
    gc = {
      automatic = true;
      interval = {Weekday = 0; Hour = 2; Minute = 0;};
      options = "--delete-older-than 30d";
    };
  };

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
