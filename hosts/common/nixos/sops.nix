{ inputs, config, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = "${inputs.self}/secrets/secrets.yaml";
    validateSopsFiles = false;
    
    # Use age key for netbird secrets
    age.keyFile = "/var/lib/sops-nix/key.txt";
    
    secrets = {
       netbird-env = {
         sopsFile = "${inputs.self}/secrets/netbird-age.env";
         format = "dotenv";
       };
    };
  };
}
