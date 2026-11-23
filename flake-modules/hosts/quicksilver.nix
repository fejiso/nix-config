{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "quicksilver";
  modules = [
    config.flake.modules.nixos.disko-btrfs
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.network-watchdog
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
