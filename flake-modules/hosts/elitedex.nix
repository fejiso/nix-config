{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "elitedex";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.emulation
    config.flake.modules.nixos.llama-rpc
  ];
  homeModules = [
    config.flake.modules.homeManager.default
  ];
}
