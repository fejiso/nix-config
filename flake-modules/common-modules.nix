{ inputs, lib, ... }: {
  options.flake.commonModules = lib.mkOption {
    type = lib.types.attrsOf (lib.types.listOf lib.types.unspecified);
    default = { };
    description = "Module lists shared by every host of a given class.";
  };

  config.flake.commonModules = {
    nixos = [
      "${inputs.self}/modules/nixos"
      "${inputs.self}/hosts/common/nixos"
      inputs.sops-nix.nixosModules.sops
      inputs.airspy-adsb-bin.nixosModules.airspy-adsb
      inputs.home-manager.nixosModules.home-manager
      { _module.args.quadlet-nix = inputs.quadlet-nix; }
    ];
    home = [
      "${inputs.self}/modules/home-manager"
      "${inputs.self}/hosts/common/home"
    ];
  };
}
