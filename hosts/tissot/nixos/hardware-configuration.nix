# Xiaomi Mi A1 (tissot) platform wiring: Mobile NixOS module set + the
# xiaomi-tissot device port (devices/xiaomi-tissot/). Cross-compiled from x86
# (kr260 pattern), same as herolte.
{ inputs, lib, ... }:

{
  imports = [
    (import "${inputs.mobile-nixos}/lib/configuration.nix" { })
    ../../../devices/xiaomi-tissot
  ];

  nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  hardware.deviceTree.enable = lib.mkDefault false;
}
