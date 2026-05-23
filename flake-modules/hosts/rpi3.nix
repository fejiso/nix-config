{ inputs, config, ... }:
let
  system = "aarch64-linux";
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.embedded
    config.flake.modules.nixos.btrfs-convert-firstboot
    "${inputs.self}/hosts/rpi3/nixos"
  ];
in
{
  flake.nixosConfigurations.rpi3 = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "rpi3";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.rpi3 = {
    deployment = {
      targetHost = null;
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "rpi3";
  };

  flake.images.rpi3 =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "rpi3";
      };
      modules = baseModules ++ [
        "${inputs.self}/hosts/rpi3/nixos/sd-image.nix"
      ];
    }).config.system.build.sdImage;
}
