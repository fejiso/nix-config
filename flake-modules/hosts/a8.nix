{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "a8";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.pentest
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
