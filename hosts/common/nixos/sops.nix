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

      pushover-app-token = {
        sopsFile = "${inputs.self}/secrets/pushover.yaml";
        key = "app_token";
      };

      pushover-user-key = {
        sopsFile = "${inputs.self}/secrets/pushover.yaml";
        key = "user_key";
      };

      openclaw-gateway-token = {
        sopsFile = "${inputs.self}/secrets/openclaw.yaml";
        key = "gateway_token";
        mode = "0444";
      };

      anthropic-api-key = {
        sopsFile = "${inputs.self}/secrets/openclaw.yaml";
        key = "anthropic_api_key";
        mode = "0444";
      };

      nix-access-tokens = {
        sopsFile = "${inputs.self}/secrets/github.yaml";
        key = "nix_access_tokens";
        mode = "0440";
        group = "nixbld";
      };
    };
  };
}
