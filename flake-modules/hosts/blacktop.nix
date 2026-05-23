{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.development
    config.flake.modules.nixos.emulation
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.adsb-readsb
    {
      home-manager.users.z-247.imports = [
        config.flake.modules.homeManager.development
        config.flake.modules.homeManager.desktop
      ];
    }
    "${inputs.self}/hosts/blacktop/nixos"
  ];
in
{
  flake.nixosConfigurations.blacktop = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "blacktop";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.blacktop = {
    deployment = {
      targetHost = "blacktop";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "blacktop";
  };
}
