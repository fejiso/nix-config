{ inputs, config, ... }:
let
  system = "aarch64-linux";
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.embedded
    config.flake.modules.nixos.btrfs-convert-firstboot
    "${inputs.self}/hosts/pine64/nixos"
  ];
in
{
  flake.nixosConfigurations.pine64 = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "pine64";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.pine64 = {
    deployment = {
      targetHost = null;
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "pine64";
  };

  flake.images.pine64 =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "pine64";
      };
      modules = baseModules ++ [
        "${inputs.self}/hosts/pine64/nixos/sd-image.nix"
      ];
    }).config.system.build.sdImage;
}
