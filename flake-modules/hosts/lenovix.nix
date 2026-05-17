{ inputs, config, ... }: {
  flake.nixosConfigurations.lenovix = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "lenovix";
    };
    modules = config.flake.commonModules.nixos ++ [
      "${inputs.self}/hosts/lenovix/nixos"
    ];
  };
}
