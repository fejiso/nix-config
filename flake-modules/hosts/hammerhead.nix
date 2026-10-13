{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "hammerhead";
    # armv7l, cross-compiled from x86 (see hosts/hammerhead/nixos).
    system = "armv7l-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    # Minimal cross-safe home (same as kr260/z-turn).
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "hammerhead.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.hammerhead =
      host.flake.nixosConfigurations.hammerhead.config.mobile.outputs.android.android-fastboot-images;
  };
}
