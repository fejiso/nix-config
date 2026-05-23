{ inputs, config, ... }: {
  flake.modules.homeManager.default = {
    imports = [
      inputs.sops-nix.homeManagerModules.sops
      # All topical home-manager modules are loaded by default so existing
      # behavior is preserved; hosts that don't want a feature should set its
      # enable option to false (most are gated on programs.<x>.enable).
      config.flake.modules.homeManager.android-tools
      config.flake.modules.homeManager.atuin-server
      config.flake.modules.homeManager.beets
      config.flake.modules.homeManager.dev-heavy
      config.flake.modules.homeManager.fish
      config.flake.modules.homeManager.git
      # gpg transitively imports gpg-agent.
      config.flake.modules.homeManager.gpg
      config.flake.modules.homeManager.ideavim
      config.flake.modules.homeManager.kanshi
      config.flake.modules.homeManager.keychain
      config.flake.modules.homeManager.mpd
      config.flake.modules.homeManager.nethack
      config.flake.modules.homeManager.niri
      config.flake.modules.homeManager.sway
      config.flake.modules.homeManager.tidalcycles
      config.flake.modules.homeManager.tmux
      config.flake.modules.homeManager.wezterm
      config.flake.modules.homeManager.zellij
      config.flake.modules.homeManager.zsh
    ];
  };
}
