{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    "${inputs.self}/hosts/a8/nixos"
  ];
in
{
  flake.nixosConfigurations.a8 = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "a8";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.a8 = {
    deployment = {
      targetHost = "a8";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "a8";
  };
}
