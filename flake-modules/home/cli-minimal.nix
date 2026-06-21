{ config, ... }: {
  # Minimal home for constrained / cross-built boards (e.g. the armv7l z-turn).
  # Self-contained on purpose (does NOT import the full `default` home), so it
  # pulls only a handful of cross-safe CLI tools + dotfiles rather than the whole
  # desktop/dev stack. It DOES share the real prompt/bat config via shell-config.
  # fish cross-compiles via the overlays/ man-page-skip override; the home `pkgs`
  # is a proper cross set (see system/home-manager.nix) so build tools resolve to
  # the build platform. No sops here: the age key isn't provisioned on a fresh
  # board, so secret decryption would fail.
  flake.modules.homeManager.cli-minimal = { pkgs, lib, ... }: {
    imports = [ config.flake.modules.homeManager.shell-config ];

    home.stateVersion = "25.05";

    # Intentional split: 26.05 system + unstable home pkgs (the global
    # _module.args.pkgs override). HM-as-a-nixos-module always evaluates against
    # the system's 26.05 nixpkgs, so the version-mismatch warning is inherent and
    # cosmetic — silence it, same as the `default` home does in home/base.nix.
    home.enableNixpkgsReleaseCheck = false;

    # The generated HM manual is useless on a headless board; skip it.
    manual.manpages.enable = false;
    manual.html.enable = false;
    manual.json.enable = false;
    news.display = "silent";

    home.packages = with pkgs; [ eza ripgrep fd fzf tree htop ];

    programs.fish = {
      enable = true;
      shellAliases = {
        ll = "eza -l";
        la = "eza -la";
        ls = "eza";
        cd = "z";
      };
      # Init the shell tools at RUNTIME. home-manager's *FishIntegration options
      # generate the config by running the tool's binary at BUILD time, which
      # can't execute the armv7l binary on the x86 cross builder (exit 126).
      interactiveShellInit = ''
        zoxide init fish | source
        direnv hook fish | source
        atuin init fish | source
        starship init fish | source
      '';
    };

    programs.git.enable = true;
    # starship itself comes from shell-config (enable + settings); just keep the
    # build-time fish integration off (we init it at runtime above).
    programs.starship.enableFishIntegration = false;
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
  };
}
