{ inputs, config, ... }:
let
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.systemd-nspawn
    config.flake.modules.nixos.media-services
    config.flake.modules.nixos.download-services
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.development
    config.flake.modules.nixos.tgtg-watcher
    config.flake.modules.nixos.emulation
    config.flake.modules.nixos.quadlet-containers
    config.flake.modules.nixos.soundcork
    {
      home-manager.users.z-247.imports = [
        config.flake.modules.homeManager.development
        config.flake.modules.homeManager.desktop
      ];
    }
    "${inputs.self}/hosts/butthead/nixos"
  ];
in
{
  flake.nixosConfigurations.butthead = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "butthead";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.butthead = {
    deployment = {
      targetHost = "butthead";
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "butthead";
  };
}
