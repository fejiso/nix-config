# Custom packages, that can be defined similarly to ones from nixpkgs
# You can build them using 'nix build .#example'
pkgs: {
  airspy-adsb = pkgs.callPackage ./airspy-adsb/default.nix { };
  # example = pkgs.callPackage ./example { };
}
