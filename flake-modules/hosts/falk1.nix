{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "falk1";
  system = "x86_64-linux";
  modules = [
    config.flake.modules.nixos.embedded
    config.flake.modules.nixos.mesh
  ];
  homeModules = [
    config.flake.modules.homeManager.cli-minimal
  ];
  targetHost = "falk1.netbird.cloud";
}
