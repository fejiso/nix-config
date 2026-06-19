{ inputs, config, lib, ... }: {
  # flake.homeConfigurations option is declared in devdesktop.nix; we only
  # contribute a new attribute here. gravidesktop is a clone of devdesktop.
  config.flake.homeConfigurations."superfer@gravidesktop" =
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        system = "aarch64-linux";
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.additions
          inputs.self.overlays.modifications
          inputs.self.overlays.unstable-packages
          # Corp network sinkholes proxy.golang.org; force Go vendor fetches
          # through GOPROXY=direct. See overlays/default.nix.
          inputs.self.overlays.go-proxy-direct
        ];
      };
      extraSpecialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "gravidesktop";
      };
      modules = [
        config.flake.modules.homeManager.default
        config.flake.modules.homeManager.development
        config.flake.modules.homeManager.opencode-work
        "${inputs.self}/hosts/gravidesktop/home"
      ];
    };
}
