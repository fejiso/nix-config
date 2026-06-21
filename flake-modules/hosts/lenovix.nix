{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "lenovix";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
