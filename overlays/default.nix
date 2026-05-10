# This file defines overlays
{inputs, ...}: {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: prev: {
  };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    retroarch-full = prev.retroarch.withCores (cores:
      prev.lib.filter (c:
        (c ? libretroCore)
        && (prev.lib.meta.availableOn prev.stdenv.hostPlatform c)
        && !(prev.lib.hasInfix "fbalpha2012" c.name)
      ) (prev.lib.attrValues cores)
    );

  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.system;
      config.allowUnfree = true;
    };
  };
}
