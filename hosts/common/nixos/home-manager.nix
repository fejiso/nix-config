{ inputs, outputs, hostname, pkgs, lib, ... }: {
  home-manager = {
    useGlobalPkgs = false;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs hostname; };

    # Explicitly tell home-manager to use nixpkgs-master
    backupFileExtension = "hm-backup";

    users.z-247 = { ... }: {
      imports = [ ../../${hostname}/home ];

      # Force home-manager to use nixpkgs-master with proper config
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
}
