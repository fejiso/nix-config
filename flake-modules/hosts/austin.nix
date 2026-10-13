{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "austin";
    # armv7l, cross-compiled from x86 (WIP port — see devices/amazon-austin).
    system = "armv7l-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "austin.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.austin =
      host.flake.nixosConfigurations.austin.config.mobile.outputs.android.android-fastboot-images;
  };
}
