{ inputs, config, ... }:
let
  host = import ../../lib/mk-host.nix {
    inherit inputs config;
    name = "tissot";
    system = "aarch64-linux";
    modules = [
      config.flake.modules.nixos.embedded
    ];
    homeModules = [
      config.flake.modules.homeManager.cli-minimal
    ];
    targetHost = "tissot.netbird.cloud";
  };
in
{
  flake = host.flake // {
    images.tissot =
      host.flake.nixosConfigurations.tissot.config.mobile.outputs.android.android-fastboot-images;
  };
}
