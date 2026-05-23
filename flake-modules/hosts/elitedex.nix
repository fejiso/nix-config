{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.emulation
    "${inputs.self}/hosts/elitedex/nixos"
  ];
in
{
  flake.nixosConfigurations.elitedex = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "elitedex";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.elitedex = {
    deployment = {
      targetHost = "elitedex";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "elitedex";
  };
}
