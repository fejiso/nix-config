{ inputs, config, ... }:
let
  system = "aarch64-linux";
  baseModules = [
    config.flake.modules.nixos.default
    config.flake.modules.nixos.embedded
    config.flake.modules.nixos.btrfs-convert-firstboot
    "${inputs.self}/hosts/xpi-s905x3/nixos"
  ];
in
{
  flake.nixosConfigurations.xpi-s905x3 = inputs.nixpkgs.lib.nixosSystem {
    inherit system;
    specialArgs = {
      inherit inputs;
      outputs = inputs.self;
      hostname = "xpi-s905x3";
    };
    modules = baseModules;
  };

  flake.colmenaNodes.xpi-s905x3 = {
    deployment = {
      targetHost = null;
      targetUser = "root";
    };
    imports = baseModules;
    _module.args.hostname = "xpi-s905x3";
  };

  flake.images.xpi-s905x3 =
    (inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {
        inherit inputs;
        outputs = inputs.self;
        hostname = "xpi-s905x3";
      };
      modules = baseModules ++ [
        "${inputs.self}/hosts/xpi-s905x3/nixos/sd-image.nix"
      ];
    }).config.system.build.sdImage;
}
