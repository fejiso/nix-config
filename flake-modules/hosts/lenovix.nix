{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "lenovix";
}
