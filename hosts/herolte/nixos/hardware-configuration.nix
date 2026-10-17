# Galaxy S7 (herolte) hardware/platform wiring: Mobile NixOS module set + the
# samsung-herolte device port (devices/samsung-herolte/). Built for aarch64 via
# binfmt — NOT cross-compiled: aarch64 has full binary-cache coverage, and the
# ancient 3.18 downstream kernel tree is happier on a native toolchain.
{ inputs, lib, ... }:

{
  imports = [
    # Mobile NixOS core module set (no built-in device; ours lives in-repo).
    # Also pulls in the mobile-nixos overlays via modules/nixpkgs.nix.
    (import "${inputs.mobile-nixos}/lib/configuration.nix" { })
    ../../../devices/samsung-herolte
  ];

  # mobile-nixos' system-target.nix sets hostPlatform to an old-style
  # lib.systems.elaborate attrset (mkDefault) which current nixpkgs rejects;
  # a plain string wins the tie via mkForce.
  nixpkgs.hostPlatform = lib.mkForce "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # The 3.18 kernel is monolithic (CONFIG_MODULES off); nixpkgs' default
  # wireguard out-of-tree module build (kernel < 5.6) can't work against the
  # mobile-nixos kernel-builder derivation anyway. Netbird falls back to its
  # bundled userspace wireguard-go.
  boot.extraModulePackages = lib.mkForce [ ];

  # No bootloader/firmware interface NixOS can talk to; the boot.img is
  # written to the BOOT partition by the boot.loader.external hook in
  # default.nix.
  hardware.deviceTree.enable = lib.mkDefault false;
}
