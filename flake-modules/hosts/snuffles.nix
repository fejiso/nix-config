{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.adsb-readsb
    config.flake.modules.nixos.adsb-feeders
    config.flake.modules.nixos.network-watchdog
    "${inputs.self}/hosts/snuffles/nixos"
  ];
in
{
  flake.nixosConfigurations.snuffles = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "snuffles";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.snuffles = {
    deployment = {
      targetHost = "snuffles";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "snuffles";
  };
}
