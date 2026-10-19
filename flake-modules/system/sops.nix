{ ... }: {
  flake.modules.nixos.cli =
{ inputs, config, ... }:

{
  imports = [ inputs.sops-nix.nixosModules.sops ];

  sops = {
    validateSopsFiles = false;

    secrets = {
      netbird-setup-key = {
        sopsFile = "${inputs.private}/secrets/netbird.yaml";
        key = "netbird_setup_key";
      };

      nordvpn-credentials = {
        sopsFile = "${inputs.private}/secrets/nordvpn.yaml";
        key = "credentials";
        mode = "0444";  # Make it readable by all so podman containers can access it
      };

      pushover-app-token = {
        sopsFile = "${inputs.private}/secrets/pushover.yaml";
        key = "app_token";
      };

      pushover-user-key = {
        sopsFile = "${inputs.private}/secrets/pushover.yaml";
        key = "user_key";
      };

      openclaw-gateway-token = {
        sopsFile = "${inputs.private}/secrets/openclaw.yaml";
        key = "gateway_token";
        mode = "0444";
      };

      openrouter-api-key = {
        sopsFile = "${inputs.private}/secrets/openrouter.yaml";
        key = "openrouter_api_key";
        mode = "0444";
      };

      opencodego-api-key = {
        sopsFile = "${inputs.private}/secrets/opencodego.yaml";
        key = "opencodego_api_key";
        mode = "0444";
      };

      kimi-api-key = {
        sopsFile = "${inputs.private}/secrets/kimi.yml";
        key = "kimi_api";
        mode = "0444";
      };

      kuma-disk-maintenance-push-url = {
        sopsFile = "${inputs.private}/secrets/kuma.yaml";
        key = "disk_maintenance_push_url";
      };

      paperless-secret-key = {
        sopsFile = "${inputs.private}/secrets/paperless.yaml";
        key = "secret_key";
        mode = "0444";
      };

      nix-builder-key = {
        sopsFile = "${inputs.private}/secrets/nix-builder.yaml";
        key = "private_key";
        owner = "nix-ssh";
        mode = "0400";
      };

      wifi-secrets = {
        sopsFile = "${inputs.private}/secrets/wifi.yaml";
        key = "";
        mode = "0400";
        # The sync unit is `wantedBy iwd.service`, so without this a wifi.yaml
        # edit + `nixos-rebuild switch` changes nothing: iwd isn't restarted
        # and the oneshot sync never re-runs. sops-nix restarts the sync when
        # the decrypted content actually changes at activation.
        restartUnits = [ "iwd-secrets-sync.service" ];
      };
    };
  };
}
;
}
