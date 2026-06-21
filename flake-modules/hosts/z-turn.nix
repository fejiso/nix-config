{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "z-turn";
  # Host platform; cross-compilation (build on x86) is set in hardware-configuration.
  system = "armv7l-linux";
  modules = [
    config.flake.modules.nixos.embedded
  ];
  # Cross-built (armv7l): a minimal cross-safe home (fish/wezterm/etc. don't
  # cross-compile). embedded.crossSafe is set in hosts/z-turn/nixos/default.nix.
  homeModules = [
    config.flake.modules.homeManager.cli-minimal
  ];
  # Built on x86 and pushed over SSH (netbird) — Cortex-A9 is too slow to build.
  targetHost = "z-turn.netbird.cloud";
  sdImage = true;
}
