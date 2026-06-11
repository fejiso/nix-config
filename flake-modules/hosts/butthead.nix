{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "butthead";
  modules = [
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.systemd-nspawn
    config.flake.modules.nixos.media-services
    config.flake.modules.nixos.download-services
    config.flake.modules.nixos.tdarr-worker
    config.flake.modules.nixos.development
    config.flake.modules.nixos.tgtg-watcher
    config.flake.modules.nixos.emulation
    config.flake.modules.nixos.quadlet-containers
    config.flake.modules.nixos.soundcork
    config.flake.modules.nixos.media-storage
    config.flake.modules.nixos.nginx-proxy-manager
    config.flake.modules.nixos.haos-vm
  ];
  homeModules = [
    config.flake.modules.homeManager.development
    config.flake.modules.homeManager.desktop
  ];
}
