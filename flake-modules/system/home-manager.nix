{ config, ... }: {
  flake.modules.nixos.default = { inputs, outputs, hostname, pkgs, lib, ... }: {
    home-manager = {
      useGlobalPkgs = false;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs outputs hostname; };

      backupFileExtension = "hm-backup";

      users.z-247 = { ... }: {
        imports = [
          config.flake.modules.homeManager.default
          "${inputs.self}/hosts/${hostname}/home"
        ];

        _module.args.pkgs = lib.mkForce (import inputs.nixpkgs-master {
          system = pkgs.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
          };
          overlays = [
            outputs.overlays.additions
            outputs.overlays.modifications
            outputs.overlays.unstable-packages
          ];
        });
      };
    };
  };
}
