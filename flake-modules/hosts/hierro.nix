{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "hierro";
  modules = [
    config.flake.modules.nixos.development
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.openclaw
  ];
  homeModules = [
    config.flake.modules.homeManager.development
  ];
}
