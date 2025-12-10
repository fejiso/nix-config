{
  description = "Multi-platform nix config for NixOS, Amazon Linux, and macOS";

  inputs = {
    # Nixpkgs
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    
    # Home manager (following unstable)
    home-manager.url = "github:nix-community/home-manager/master";
    home-manager.inputs.nixpkgs.follows = "nixpkgs-unstable";
    
    # Hardware configurations for NixOS
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";
    
    # Darwin support for macOS
    nix-darwin.url = "github:LnL7/nix-darwin";
    
    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

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
    
  in {
    
    # Formatter
    formatter = forAllSystems (system: nixpkgs.legacyPackages.${system}.alejandra);
    
    # Overlays
    overlays = import ./overlays {inherit inputs;};
    
    # Modules
    nixosModules = import ./modules/nixos;
    darwinModules = import ./modules/darwin;
    
    # NixOS configurations
    nixosConfigurations = {
      elitedex = mkNixosSystem "elitedex" "x86_64-linux";
      lenovix = mkNixosSystem "lenovix" "x86_64-linux";
      a8 = mkNixosSystem "a8" "x86_64-linux";
      blacktop = mkNixosSystem "blacktop" "x86_64-linux";
      hierro = mkNixosSystem "hierro" "x86_64-linux";
      butthead = mkNixosSystem "butthead" "x86_64-linux";
    };
    
    # Standalone home-manager configurations (for non-NixOS systems)
    homeConfigurations = {
      "superfer@devdesktop" = mkHomeConfiguration "devdesktop" "superfer" "x86_64-linux";
    };
    
    # Darwin configurations (macOS)
    darwinConfigurations = {
      work-laptop = mkDarwinSystem "work-laptop" "aarch64-darwin";
    };
  };
}