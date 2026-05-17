{ inputs, ... }: {
  flake.overlays = import "${inputs.self}/overlays" { inherit inputs; };
}
