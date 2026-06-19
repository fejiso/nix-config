{ inputs, config, ... }: {
  # Cross-platform home-manager defaults. Linux-only modules (Wayland tooling
  # etc.) live in linux-default.nix.
  flake.modules.homeManager.default = {
    imports = [
      inputs.sops-nix.homeManagerModules.sops
      inputs.noctalia.homeModules.default
      # All cross-platform topical home-manager modules are loaded by default
      # so existing behavior is preserved; hosts that don't want a feature
      # should set its enable option to false (most are gated on
      # programs.<x>.enable).
      #
      # Media modules (beets, mpd, tidalcycles) are NOT here — they live in the
      # `desktop` module so they only land on real desktops. beets in particular
      # installs unconditionally (no enable gate), so leaving it here pulled
      # beets + its media deps onto every host using `default` (devdesktop, etc.).
      config.flake.modules.homeManager.android-tools
      config.flake.modules.homeManager.atuin-server
      config.flake.modules.homeManager.dev-heavy
      config.flake.modules.homeManager.fish
      config.flake.modules.homeManager.git
      # gpg transitively imports gpg-agent.
      config.flake.modules.homeManager.gpg
      config.flake.modules.homeManager.ideavim
      config.flake.modules.homeManager.keychain
      config.flake.modules.homeManager.nethack
      config.flake.modules.homeManager.wezterm
      config.flake.modules.homeManager.zellij
      config.flake.modules.homeManager.zsh
    ];
  };
}
