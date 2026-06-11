# Standard wiring for a NixOS host: builds flake.nixosConfigurations.<name>,
# flake.colmenaNodes.<name> and (optionally) flake.images.<name> from a single
# declaration. Each flake-modules/hosts/<name>.nix imports this with its
# host-specific arguments; hosts with a different shape (standalone
# home-manager, darwin) don't use it.
{
  inputs,
  config,
  # Host name: attribute name, hostname specialArg and hosts/<name>/nixos path.
  name,
  system ? "x86_64-linux",
  # Opt-in flake.modules.nixos.* beyond `default`.
  modules ? [ ],
  # home-manager modules imported for the primary user.
  homeModules ? [ ],
  homeUser ? "z-247",
  # Colmena deploy target; null for hosts deployed by SD image instead of SSH.
  targetHost ? name,
  # Also build flake.images.<name> from hosts/<name>/nixos/sd-image.nix.
  sdImage ? false,
}:
let
  lib = inputs.nixpkgs.lib;
  specialArgs = {
    inherit inputs;
    outputs = inputs.self;
    hostname = name;
  };
  baseModules =
    [ config.flake.modules.nixos.default ]
    ++ modules
    ++ lib.optional (homeModules != [ ]) {
      home-manager.users.${homeUser}.imports = homeModules;
    }
    ++ [ "${inputs.self}/hosts/${name}/nixos" ];
in
{
  flake = {
    nixosConfigurations.${name} = inputs.nixpkgs.lib.nixosSystem {
      inherit system specialArgs;
      modules = baseModules;
    };

    colmenaNodes.${name} = {
      deployment = {
        inherit targetHost;
        targetUser = "root";
      };
      imports = baseModules;
      _module.args.hostname = name;
    };
  } // lib.optionalAttrs sdImage {
    images.${name} =
      (inputs.nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = baseModules ++ [
          "${inputs.self}/hosts/${name}/nixos/sd-image.nix"
        ];
      }).config.system.build.sdImage;
  };
}
