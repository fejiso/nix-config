{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "mustang";
    # armv7l, cross-compiled from x86 (WIP port — see devices/amazon-mustang).
    system = "armv7l-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "mustang.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.mustang =
      host.flake.nixosConfigurations.mustang.config.mobile.outputs.android.android-fastboot-images;
  };
}
