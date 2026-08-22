{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "hierro";
  modules = [
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.development
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.openclaw
    config.flake.modules.nixos.llama-rpc
  ];
  homeModules = [
    config.flake.modules.homeManager.default
    config.flake.modules.homeManager.development
  ];
}
