{ config, ... }: {
  flake.modules.nixos.default = { inputs, outputs, hostname, pkgs, lib, ... }: {
    home-manager = {
      useGlobalPkgs = false;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs outputs hostname; };

      backupFileExtension = "hm-backup";

      users.z-247 = { ... }: {
        imports = [
          # Every NixOS host is Linux, so use linux-default (which transitively
          # imports default plus Wayland tooling).
          config.flake.modules.homeManager.linux-default
          "${inputs.self}/hosts/${hostname}/home"
        ];

        _module.args.pkgs = lib.mkForce (import inputs.nixpkgs-unstable {
          system = pkgs.stdenv.hostPlatform.system;
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              "electron-39.8.10"
            ];
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
