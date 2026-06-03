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

    # niri 26.04 leaks VRAM whenever monitors are powered off (e.g. hypridle's
    # 30-min `power-off-monitors`), eventually filling the GPU and starving
    # CUDA training on butthead. Upstream: niri-wm/niri#3295; the fix is the
    # still-unmerged PR #3910. Rather than build a third-party fork branch, we
    # apply that PR's diff on top of nixpkgs' official v26.04 release source.
    # The patch applies cleanly to v26.04 and is code-only (Cargo.lock and thus
    # cargoHash unchanged). Drop this once the fix lands in a nixpkgs niri bump.
    niri = prev.niri.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/niri-3910-vram-leak-monitors-off.patch
      ];
    });
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
