{
  description = "Multi-platform nix config for NixOS, Amazon Linux, and macOS";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    nixpkgs-master.url = "github:nixos/nixpkgs/master";

    # Home manager (following master to get latest neovimUtils)
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-master";
    
    # Hardware configurations for NixOS
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    
    # Darwin support for macOS
    nix-darwin.url = "github:LnL7/nix-darwin";
    
    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Colmena for deployment
    colmena.url = "github:zhaofengli/colmena";

    # Quadlet-nix for podman container management
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    # Airspy ADS-B source
    airspy-adsb-bin.url = "github:fejiso/airspy_adsb/master";
    #airspy-adsb-bin.follows = "nixpkgs";

    };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    home-manager,
    nixos-hardware,
    nix-darwin,
    sops-nix,
    colmena,
    quadlet-nix,
    airspy-adsb-bin,
    ...
  } @ inputs: let
    inherit (self) outputs;
    
    # Supported systems
    systems = [
      "aarch64-linux"
      "i686-linux"
      "x86_64-linux"
      "aarch64-darwin"
      "x86_64-darwin"
    ];
    
    forAllSystems = nixpkgs.lib.genAttrs systems;
    
    # Common configuration shared across all systems
    commonModules = {
      nixos = [
        ./modules/nixos
        ./hosts/common/nixos
        sops-nix.nixosModules.sops
        airspy-adsb-bin.nixosModules.airspy-adsb
        home-manager.nixosModules.home-manager
        # Pass quadlet-nix to modules via specialArgs
        { _module.args.quadlet-nix = quadlet-nix; }
      ];
      home = [
        ./modules/home-manager
        ./hosts/common/home
      ];
    };
    
    # Helper function to create nixos configurations
    mkNixosSystem = hostname: system: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs outputs hostname;};
      modules = commonModules.nixos ++ [
        ./hosts/${hostname}/nixos
      ];
    };
    
    # Helper function to create home-manager configurations
    mkHomeConfiguration = hostname: username: system: home-manager.lib.homeManagerConfiguration {
      pkgs = nixpkgs.legacyPackages.${system};
      extraSpecialArgs = {inherit inputs outputs hostname;};
      modules = commonModules.home ++ [
        ./hosts/${hostname}/home
      ];
    };
    
    # Helper function to create darwin configurations
    mkDarwinSystem = hostname: system: nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = {inherit inputs outputs hostname;};
      modules = [
        ./hosts/${hostname}/darwin
        home-manager.darwinModules.home-manager
        {
          home-manager = {
            useGlobalPkgs = true;
            useUserPackages = true;
            extraSpecialArgs = {inherit inputs outputs hostname;};
            users.superfer = import ./hosts/${hostname}/home;
          };
        }
      ];
    };

    # Helper function to create SD image configurations
    mkSdImageSystem = hostname: system: baseConfig: nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = {inherit inputs outputs hostname;};
      modules = commonModules.nixos ++ [
        baseConfig
        ./hosts/${hostname}/nixos/sd-image.nix
      ];
    };
    
  in {
    
    # Formatter
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    
    # Overlays
    overlays = import ./overlays {inherit inputs;};
    
    # Modules
    nixosModules = import ./modules/nixos;
    darwinModules = import ./modules/darwin;

    # Colmena configuration
    colmena = let
      mkColmena = name: {
        deployment = {
          targetHost = name;
          targetUser = "root";
        };
        imports = commonModules.nixos ++ [ ./hosts/${name}/nixos ];
        _module.args.hostname = name;
      };
      mkColmenaBuildOnly = name: {
        deployment = {
          targetHost = null;
        };
        imports = commonModules.nixos ++ [ ./hosts/${name}/nixos ];
        _module.args.hostname = name;
      };
    in {
      meta = {
        nixpkgs = import nixpkgs {
          system = "x86_64-linux";
        };
        specialArgs = { inherit inputs outputs; };
      };

      # x86_64 hosts
      elitedex = mkColmena "elitedex";
      lenovix = mkColmena "lenovix";
      hispanas = mkColmena "hispanas";
      a8 = mkColmena "a8";
      blacktop = mkColmena "blacktop";
      hierro = mkColmena "hierro";
      butthead = mkColmena "butthead";
      snuffles = mkColmena "snuffles";

      # ARM hosts (build-only, no deployment)
      rpi3 = mkColmenaBuildOnly "rpi3";
      pine64 = mkColmenaBuildOnly "pine64";
      xpi-s905x3 = mkColmenaBuildOnly "xpi-s905x3";
    };
    
    # NixOS configurations
    nixosConfigurations = {
      # x86_64 hosts
      elitedex = mkNixosSystem "elitedex" "x86_64-linux";
      lenovix = mkNixosSystem "lenovix" "x86_64-linux";
      hispanas = mkNixosSystem "hispanas" "x86_64-linux";
      a8 = mkNixosSystem "a8" "x86_64-linux";
      blacktop = mkNixosSystem "blacktop" "x86_64-linux";
      hierro = mkNixosSystem "hierro" "x86_64-linux";
      butthead = mkNixosSystem "butthead" "x86_64-linux";
      snuffles = mkNixosSystem "snuffles" "x86_64-linux";

      # ARM hosts
      rpi3 = mkNixosSystem "rpi3" "aarch64-linux";
      pine64 = mkNixosSystem "pine64" "aarch64-linux";
      xpi-s905x3 = mkNixosSystem "xpi-s905x3" "aarch64-linux";
    };
    
    # Standalone home-manager configurations (for non-NixOS systems)
    homeConfigurations = {
      "superfer@devdesktop" = mkHomeConfiguration "devdesktop" "superfer" "x86_64-linux";
    };

    # SD card images for ARM devices
    images = {
      rpi3 = (mkSdImageSystem "rpi3" "aarch64-linux" ./hosts/rpi3/nixos).config.system.build.sdImage;
      pine64 = (mkSdImageSystem "pine64" "aarch64-linux" ./hosts/pine64/nixos).config.system.build.sdImage;
      xpi-s905x3 = (mkSdImageSystem "xpi-s905x3" "aarch64-linux" ./hosts/xpi-s905x3/nixos).config.system.build.sdImage;
    };

    # Darwin configurations (macOS)
    darwinConfigurations = {
      work-laptop = mkDarwinSystem "work-laptop" "aarch64-darwin";
    };
  };
}
