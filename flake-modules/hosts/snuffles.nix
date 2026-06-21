{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "snuffles";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.adsb-readsb
    config.flake.modules.nixos.adsb-feeders
    config.flake.modules.nixos.network-watchdog
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
