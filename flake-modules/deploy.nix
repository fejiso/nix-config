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

  config.perSystem = { system, ... }: {
    # Expose `nix run .#deploy` alongside the existing `nix run .#colmena`.
    packages.deploy = inputs.deploy-rs.packages.${system}.default;

    # `nix flake check` runs deploy-rs's per-node validators.
    checks = inputs.deploy-rs.lib.${system}.deployChecks config.flake.deploy;
  };
}
