{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.novasdr
    {
      home-manager.users.z-247.imports = [
        config.flake.modules.homeManager.development
        config.flake.modules.homeManager.desktop
      ];
    }
    "${inputs.self}/hosts/hispanas/nixos"
  ];
in
{
  flake.nixosConfigurations.hispanas = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "hispanas";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.hispanas = {
    deployment = {
      targetHost = "hispanas";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "hispanas";
  };
}
