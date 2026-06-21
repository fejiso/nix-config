{ ... }: {
  # Minimal home for constrained / cross-built boards (e.g. the armv7l z-turn).
  # Self-contained on purpose (does NOT import the full `default` home), so it
  # pulls only a handful of cross-safe CLI tools + dotfiles rather than the whole
  # desktop/dev stack. fish cross-compiles via the overlays/ man-page-skip
  # override; the home `pkgs` is a proper cross set (see system/home-manager.nix)
  # so build tools resolve to the build platform. No sops here: the age key isn't
  # provisioned on a fresh board, so secret decryption would fail.
  flake.modules.homeManager.cli-minimal =
{ config, pkgs, lib, ... }: {
  home.stateVersion = "25.05";

  # The generated HM manual is useless on a headless board; skip it.
  manual.manpages.enable = false;
  manual.html.enable = false;
  manual.json.enable = false;
  news.display = "silent";

  home.packages = with pkgs; [ eza bat ripgrep fd fzf tree htop ];

  programs.fish = {
    enable = true;
    shellAliases = {
      ll = "eza -l";
      la = "eza -la";
      ls = "eza";
      cat = "bat";
      cd = "z";
    };
    # Init the shell tools at RUNTIME. home-manager's *FishIntegration options
    # generate the config by running the tool's binary at BUILD time, which
    # can't execute the armv7l binary on the x86 cross builder (exit 126). Doing
    # it here runs the (working) armv7l binaries on the board at shell startup.
    interactiveShellInit = ''
      zoxide init fish | source
      direnv hook fish | source
      atuin init fish | source
      starship init fish | source
    '';
  };

  programs.git.enable = true;
  programs.starship = {
    enable = true;
    enableFishIntegration = false;
  };
  programs.zoxide = {
    enable = true;
    enableFishIntegration = false;
  };
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
    enableFishIntegration = false;
  };
  programs.atuin = {
    enable = true;
    enableFishIntegration = false;
    settings.auto_sync = false;
  };
}
;
}
