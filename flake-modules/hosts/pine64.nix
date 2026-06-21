{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "pine64";
  system = "aarch64-linux";
  modules = [
    config.flake.modules.nixos.embedded
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
  targetHost = null;
  sdImage = true;
}
