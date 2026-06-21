{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "hispanas";
  modules = [
    config.flake.modules.nixos.novasdr
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
  ];
  homeModules = [
    config.flake.modules.homeManager.linux-default
    config.flake.modules.homeManager.development
    config.flake.modules.homeManager.desktop
  ];
}
