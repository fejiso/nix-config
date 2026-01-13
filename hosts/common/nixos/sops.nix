{ inputs, config, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    defaultSopsFile = "${inputs.self}/secrets/secrets.yaml";
    validateSopsFiles = false;

    secrets = {
      netbird-setup-key = {
        sopsFile = "${inputs.self}/secrets/netbird.yaml";
        key = "netbird_setup_key";
      };

      nordvpn-credentials = {
        sopsFile = "${inputs.self}/secrets/nordvpn.yaml";
        key = "credentials";
        mode = "0444";  # Make it readable by all so podman containers can access it
      };
    };
  };
}
