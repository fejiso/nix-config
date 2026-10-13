{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "thor";
    # armv7l, cross-compiled from x86 (WIP port — see devices/amazon-thor).
    system = "armv7l-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "thor.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.thor =
      host.flake.nixosConfigurations.thor.config.mobile.outputs.android.android-fastboot-images;
  };
}
