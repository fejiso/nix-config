{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "hispanas";
  modules = [
    config.flake.modules.nixos.novasdr
  ];
  homeModules = [
    config.flake.modules.homeManager.development
    config.flake.modules.homeManager.desktop
  ];
}
