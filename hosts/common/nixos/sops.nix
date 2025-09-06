{ inputs, config, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = "${inputs.self}/secrets/secrets.yaml";
    validateSopsFiles = false;
    
    # Use SSH host keys for system-level secrets
    age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
    
    secrets = {
      # System-level secrets go here
      # Example for netbird:
      # netbird-setup-key = {
      #   sopsFile = "${inputs.self}/secrets/netbird.env";
      #   format = "dotenv";
      #   key = "NB_SETUP_KEY";
      # };
    };
  };
}
