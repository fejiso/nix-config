# Nexus 5 (hammerhead) platform wiring: Mobile NixOS module set + the
# lg-hammerhead device port (devices/lg-hammerhead/). armv7l — pure
# cross-compile from x86 (no armv7l builders, no binfmt), same pattern as the
# z-turn.
{ inputs, lib, ... }:

{
  imports = [
    (import "${inputs.mobile-nixos}/lib/configuration.nix" { })
    ../../../devices/lg-hammerhead
  ];

  # See hosts/herolte for why the mkForce (mobile-nixos sets an old-style
  # elaborated platform set at mkDefault that current nixpkgs rejects).
  nixpkgs.hostPlatform = lib.mkForce "armv7l-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  hardware.deviceTree.enable = lib.mkDefault false;
}
