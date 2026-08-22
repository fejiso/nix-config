{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "blacktop";
  modules = [
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.desktop-services
    config.flake.modules.nixos.mesh
    config.flake.modules.nixos.laptop
    config.flake.modules.nixos.development
    config.flake.modules.nixos.emulation
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.adsb-readsb
    config.flake.modules.nixos.llama-rpc
  ];
  homeModules = [
    config.flake.modules.homeManager.linux-default
    config.flake.modules.homeManager.development
    config.flake.modules.homeManager.desktop
  ];
}
