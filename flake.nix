{
  description = "Multi-platform nix config for NixOS, Amazon Linux, and macOS (dendritic)";

  inputs = {
    # Dendritic pattern
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    # Nixpkgs: stable by default; unstable only for explicit per-package picks.
    nixpkgs.url = "github:nixos/nixpkgs/nixos-26.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";

    # Home Manager tracks the same stable nixpkgs as the system by default.
    # Use `pkgs.unstable` selectively for packages that need to move faster.
    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    # Hardware configurations for NixOS
    nixos-hardware.url = "github:NixOS/nixos-hardware/master";

    # Darwin support for macOS, also on stable nixpkgs by default
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    # Secrets management
    sops-nix.url = "github:Mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";

    # Colmena for deployment (NixOS hosts)
    colmena.url = "github:zhaofengli/colmena";

    # polystack trading bot (dendritic fleet: hierro root/trade host +
    # zenoh router, butthead observe/soak leaf; see polystack docs/deploy.md).
    # Branch soaks: add a second input pinned at the branch and point the soak
    # instance's `package` at it, e.g.
    #   polystack-soak.url = "git+ssh://forgejo@hierro.netbird.cloud:2222/fer/polystack.git?ref=<branch>";
    polystack.url = "git+ssh://forgejo@hierro.netbird.cloud:2222/fer/polystack.git";

    # deploy-rs for deployment (home-manager on foreign distros, etc.)
    deploy-rs.url = "github:serokell/deploy-rs";
    deploy-rs.inputs.nixpkgs.follows = "nixpkgs";

    # Quadlet-nix for podman container management
    quadlet-nix.url = "github:SEIAROTg/quadlet-nix";

    # Airspy ADS-B source
    airspy-adsb-bin.url = "github:fejiso/airspy_adsb/master";

    # Noctalia desktop shell (fast-moving; intentional unstable exception)
    noctalia = {
      url = "github:noctalia-dev/noctalia";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };

    # FPGA vendor toolchains (FHS-wrapped; user supplies the installers).
    # nix-fpga covers Vivado + Quartus; nix-gowin-eda wraps Gowin EDA.
    # NB: do NOT make these follow our nixpkgs — nix-fpga's FHS env references
    # libstdcxx5, removed from newer nixpkgs, so it only builds against its own
    # pin. Its FHS glibc is therefore older than the host's (2.42): run the
    # installer non-interactively (`vivado-shell -c '<installer>'`) so the
    # interactive shell's glibc-2.42 tools aren't loaded inside the sandbox.
    nix-fpga.url = "git+https://codeberg.org/Rutherther/nix-fpga";
    nix-gowin-eda.url = "github:scottwillmoore/nix-gowin-eda";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./flake-modules);
}
