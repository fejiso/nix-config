{ inputs, config, lib, ... }: {
  options.flake.darwinConfigurations = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.unspecified;
    default = { };
    description = "nix-darwin configurations.";
  };

  config.flake.darwinConfigurations.work-laptop = inputs.nix-darwin.lib.darwinSystem {
    system = "aarch64-darwin";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "work-laptop";
    };
    modules = [
      "${inputs.self}/hosts/work-laptop/darwin"
    ];
  };
}
