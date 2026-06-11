{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "pine64";
  system = "aarch64-linux";
  modules = [
    config.flake.modules.nixos.embedded
    config.flake.modules.nixos.btrfs-convert-firstboot
  ];
  targetHost = null;
  sdImage = true;
}
