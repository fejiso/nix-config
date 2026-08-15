{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "lenovix";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.tdarr-worker
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
