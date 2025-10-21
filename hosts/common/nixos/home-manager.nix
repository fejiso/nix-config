{ inputs, outputs, hostname, ... }: {
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    extraSpecialArgs = { inherit inputs outputs hostname; };
    
    users.z-247 = import ../../${hostname}/home;
  };
}
