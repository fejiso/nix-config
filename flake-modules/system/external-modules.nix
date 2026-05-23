{ inputs, config, ... }: {
  flake.modules.nixos.default = {
    imports = [
      inputs.sops-nix.nixosModules.sops
      inputs.airspy-adsb-bin.nixosModules.airspy-adsb
      inputs.home-manager.nixosModules.home-manager
      config.flake.modules.nixos.nfs-mounts
      config.flake.modules.nixos.backup
      config.flake.modules.nixos.storagebox-mount
      { _module.args.quadlet-nix = inputs.quadlet-nix; }
    ];
  };
}
