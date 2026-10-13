# Kindle Fire HDX 7 (thor) platform wiring: Mobile NixOS module
# set + the amazon-thor device port (devices/amazon-thor/ — WIP, see its
# comments). armv7l, pure cross-compile from x86 (z-turn pattern).
{ inputs, lib, ... }:

{
  imports = [
    (import "${inputs.mobile-nixos}/lib/configuration.nix" { })
    ../../../devices/amazon-thor
  ];

  # mkForce: mobile-nixos sets an old-style elaborated platform set at
  # mkDefault that current nixpkgs rejects.
  nixpkgs.hostPlatform = lib.mkForce "armv7l-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # Pre-5.6 kernels trigger nixpkgs' default out-of-tree wireguard module
  # build, which can't work against a kernel-builder derivation.
  boot.extraModulePackages = lib.mkForce [ ];

  hardware.deviceTree.enable = lib.mkDefault false;
}
