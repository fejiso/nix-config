{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "ford";
    # armv7l, cross-compiled from x86 (WIP port — see devices/amazon-ford).
    system = "armv7l-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "ford.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.ford =
      host.flake.nixosConfigurations.ford.config.mobile.outputs.android.android-fastboot-images;
  };
}
