{ inputs, lib, config, ... }: {
  options.flake.colmenaNodes = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = "Per-host colmena node configurations.";
  };

  config.flake.colmenaHive = inputs.colmena.lib.makeHive ({
    meta = {
      nixpkgs = import inputs.nixpkgs {
        system = "x86_64-linux";
      };
      specialArgs = {
        inherit inputs;
        outputs = inputs.self;
      };
    };
  } // config.flake.colmenaNodes);

  config.perSystem = { system, ... }: {
    packages.colmena = inputs.colmena.packages.${system}.colmena;
  };
}
