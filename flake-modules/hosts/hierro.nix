{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    # Opt-in nixos features.
    config.flake.modules.nixos.development
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.openclaw
    # Opt-in home-manager features.
    {
      home-manager.users.z-247.imports = [
        config.flake.modules.homeManager.development
      ];
    }
    "${inputs.self}/hosts/hierro/nixos"
  ];
in
{
  flake.nixosConfigurations.hierro = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "hierro";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.hierro = {
    deployment = {
      targetHost = "hierro";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "hierro";
  };
}
