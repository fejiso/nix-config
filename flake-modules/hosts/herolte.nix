{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "herolte";
    system = "aarch64-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    # Minimal cross-safe home (same as kr260).
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    # Cross-compiled from x86, deployed over SSH/netbird like kr260/z-turn.
    targetHost = "herolte.netbird.cloud";
    # No sdImage: the flashable artifacts (boot.img + rootfs + heimdall
    # script) are a build product of the base configuration itself, via
    # mobile-nixos' android system-type outputs.
  };
in
{
  flake = host.flake // {
    images.herolte =
      host.flake.nixosConfigurations.herolte.config.mobile.outputs.android.android-fastboot-images;
  };
}
