{ inputs, config, ... }:
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "kr260";
  # Host platform; cross-compilation (build on x86) is set in hardware-configuration.
  system = "aarch64-linux";
  modules = [
    config.flake.modules.nixos.embedded
  ];
  # Cross-built (aarch64): a minimal cross-safe home (fish/wezterm/etc. don't
  # cross-compile). embedded.crossSafe is set in hosts/kr260/nixos/default.nix.
  homeModules = [
    config.flake.modules.homeManager.cli-minimal
  ];
  # Built on x86 and pushed over SSH (netbird) — avoids the amp1 native-builder
  # round-trip and keeps the board deployable without emulation. Mirrors z-turn.
  targetHost = "kr260.netbird.cloud";
  sdImage = true;
}
