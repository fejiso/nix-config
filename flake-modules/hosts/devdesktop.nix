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
      };
      extraSpecialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "devdesktop";
      };
      modules = [
        config.flake.modules.homeManager.default
        "${inputs.self}/hosts/devdesktop/home"
      ];
    };
}
