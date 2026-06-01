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

    # Nixpkgs ships colmena 0.4.0, which only supports the legacy
    # outputs.colmena API. Use the flake input (0.5.0-pre) for colmenaHive.
    colmena = inputs.colmena.packages.${final.stdenv.hostPlatform.system}.colmena;

    # pipx 1.8.0 tests fail against newer `packaging` library (whitespace
    # formatting mismatches in test_package_specifier). Runtime is unaffected.
    pipx = prev.pipx.overridePythonAttrs (_: { doCheck = false; });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      system = final.stdenv.hostPlatform.system;
      config.allowUnfree = true;
    };
  };
}
