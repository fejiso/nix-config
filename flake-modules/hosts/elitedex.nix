{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "elitedex";
  modules = [
    config.flake.modules.nixos.emulation
  ];
}
