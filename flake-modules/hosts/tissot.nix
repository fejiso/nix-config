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

  # lk2nd-msm8953: the secondary bootloader that must be flashed to tissot's
  # `boot` partition once before any NixOS image (see ANDROID-EDGE-DEVICES.md).
  # Built for x86 hosts (it's a bare-metal blob; gcc-arm-embedded does the
  # ARM part):  nix build .#lk2nd-msm8953
  perSystem = { system, ... }: {
    packages.lk2nd-msm8953 =
      let
        pkgs = import inputs.nixpkgs {
          inherit system;
          overlays = [ (import "${inputs.mobile-nixos}/overlay/overlay.nix") ];
        };
      in
      pkgs.lk2ndMsm8953;
  };
}
