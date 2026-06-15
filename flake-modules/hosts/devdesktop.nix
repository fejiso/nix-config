{ inputs, config, lib, ... }: {
  options.flake.homeConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
    description = "Standalone home-manager configurations (non-NixOS hosts).";
  };

  config.flake.homeConfigurations."superfer@devdesktop" =
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
        config.allowUnfree = true;
        overlays = [
          inputs.self.overlays.additions
          inputs.self.overlays.modifications
          inputs.self.overlays.unstable-packages
          # devdesktop's corp network sinkholes proxy.golang.org; force Go
          # vendor fetches through GOPROXY=direct. See overlays/default.nix.
          inputs.self.overlays.go-proxy-direct
        ];
      };
      extraSpecialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "devdesktop";
      };
      modules = [
        config.flake.modules.homeManager.default
        config.flake.modules.homeManager.development
        config.flake.modules.homeManager.opencode-work
        "${inputs.self}/hosts/devdesktop/home"
      ];
    };
}
