{ inputs, config, lib, ... }: {
  options.flake.deploy = lib.mkOption {
    type = lib.types.lazyAttrsOf lib.types.raw;
    default = { };
    description = ''
      deploy-rs configuration. Co-exists with colmena: colmena handles
      NixOS hosts (flake.colmenaHive), deploy-rs handles home-manager
      activations on foreign distros (flake.deploy.nodes).
    '';
  };

  config.flake.deploy.nodes.amp1 = {
    hostname = "amp1.netbird.cloud";
    profiles.ubuntu = {
      user = "ubuntu";
      path =
        inputs.deploy-rs.lib.aarch64-linux.activate.home-manager
          config.flake.homeConfigurations."ubuntu@amp1";
    };
  };

  config.perSystem = { system, ... }: {
    # Expose `nix run .#deploy` alongside the existing `nix run .#colmena`.
    packages.deploy = inputs.deploy-rs.packages.${system}.default;

    # `nix flake check` runs deploy-rs's per-node validators.
    checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
  };
}
