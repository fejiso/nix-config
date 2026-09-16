{ inputs, config, ... }: {
  # flake.homeConfigurations option is declared in devdesktop.nix; we only
  # contribute a new attribute here.
  config.flake.homeConfigurations."ubuntu@amp1" =
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        system = "aarch64-linux";
        config.allowUnfree = true;
        # Stable base with pkgs.unstable available for the explicit exceptions
        # used by shared home modules (e.g. antigravity-cli).
        overlays = [ inputs.self.overlays.unstable-packages ];
      };
      extraSpecialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "amp1";
      };
      modules = [
        # Server-only host; no Wayland tooling.
        config.flake.modules.homeManager.default
        "${inputs.self}/hosts/amp1/home"
      ];
    };
}
