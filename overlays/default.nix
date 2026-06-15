# This file defines overlays
{inputs, ...}:
let
  # Wrap a buildGo*Module so its vendor (go-modules) derivation fetches with
  # GOPROXY=direct / GOSUMDB=off. See the long note on `buildGoModule` below
  # for why this is done in-sandbox via overrideModAttrs rather than `env`.
  goProxyDirect = builder: args:
    let
      lib = inputs.nixpkgs.lib;
      # Append our GOPROXY exports to the modules derivation's preBuild,
      # composing with any overrideModAttrs the package already defines.
      inject = a: a // {
        overrideModAttrs = lib.composeExtensions
          (a.overrideModAttrs or (_: _: { }))
          (_finalAttrs: prevAttrs: {
            preBuild = (prevAttrs.preBuild or "") + ''
              export GOPROXY=direct
              export GOSUMDB=off
            '';
          });
      };
    in
    # buildGoModule accepts either an attrset or a fixed-point function
    # (finalAttrs: {...}, via lib.extendMkDerivation) — handle both.
    builder (
      if builtins.isFunction args
      then (finalAttrs: inject (args finalAttrs))
      else inject args
    );
in {
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

    # pa-dlna 1.2 rejects an entire UPnP device if ANY of its services has a
    # non-UPnP SCPD namespace. The Bose SoundTouch advertises a Tencent "QPlay"
    # service (urn:schemas-tencent-com:...) next to the standard MediaRenderer
    # services, so pa-dlna throws and never creates a sink. Patch it to skip
    # non-UPnP services. Drop if fixed upstream.
    pa-dlna = prev.pa-dlna.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/pa-dlna-skip-non-upnp-services.patch
      ];
    });

    # perl5.42.0-DBD-CSV-0.60 fails 3/73 tests (t/70_csv.t: drop table tests).
    # Runtime is unaffected. Cascades through parallel-full → system-path.
    # Drop when fixed upstream in nixpkgs.
    perlPackages = prev.perlPackages // {
      DBDCSV = prev.perlPackages.DBDCSV.overrideAttrs (_: { doCheck = false; });
    };
  };

  # Force every buildGo*Module vendor fetch through GOPROXY=direct / GOSUMDB=off.
  #
  # This is applied ONLY on devdesktop (a corp machine), NOT globally: that
  # network sinkholes proxy.golang.org and sum.golang.org (the TLS cert served
  # is for chalupa-dns-sinkhole.corp.amazon.com), so the default GOPROXY can't
  # fetch module zips — every `*-go-modules` fixed-output derivation fails (e.g.
  # sops-nix's sops-install-secrets). GOPROXY=direct fetches modules straight
  # from their VCS (github etc.), which IS reachable; GOSUMDB=off skips the
  # equally-sinkholed checksum database. Integrity is still guaranteed by Nix's
  # vendorHash, so disabling the sumdb is safe.
  #
  # We do NOT want this elsewhere: on normal networks proxy.golang.org is
  # reachable and gives module zips + binary-cache hits, whereas `direct` makes
  # dependency-heavy packages (e.g. rclone) issue hundreds of `git ls-remote`
  # calls that GitHub rate-limits with HTTP 401, breaking the build.
  #
  # It MUST be set inside the build sandbox, not via `env`: GOPROXY is listed
  # in the go-modules FOD's `impureEnvVars` (build-support/go/module.nix), so
  # any `env.GOPROXY` is clobbered at build time by the daemon's ambient
  # GOPROXY (empty -> Go falls back to its baked-in proxy default). We therefore
  # export it in the modules derivation's preBuild via overrideModAttrs,
  # composing with any the package already defines. Only the FOD needs this; the
  # main build phase already runs with GOPROXY=off against the vendored output.
  #
  # Note: this changes the derivation hash of every Go package, so prebuilt
  # binaries from cache.nixos.org won't be reused — but on devdesktop's network
  # those uncached builds would fail to fetch deps anyway.
  # Wrap every builder matching buildGo*Module (buildGoModule, buildGo123Module,
  # buildGo124Module, ...) rather than a hardcoded list, so new versioned
  # builders added by nixpkgs bumps are covered automatically. The filter only
  # inspects attribute *names*, so it doesn't force evaluation of package values.
  go-proxy-direct = _final: prev:
    inputs.nixpkgs.lib.mapAttrs (_: goProxyDirect)
      (inputs.nixpkgs.lib.filterAttrs
        (n: _: builtins.match "buildGo[0-9]*Module" n != null)
        prev);

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable =
      let
        unstablePkgs = import inputs.nixpkgs-unstable {
          system = final.stdenv.hostPlatform.system;
          config.allowUnfree = true;
        };
      in
      unstablePkgs.extend (ufinal: uprev: {
        # kilo (kilocode-cli) 7.3.40 builds kilo-console with vite, whose
        # node_modules scripts carry a #!/usr/bin/env node shebang. The package
        # runs patchShebangs but has only `bun` in its inputs, so patchShebangs
        # can't resolve `node` and leaves the broken shebang — vite then fails
        # with "/usr/bin/env: bad interpreter" in the sandbox. Add nodejs so the
        # shebang resolves, and re-run patchShebangs after configure (the FOD's
        # files are read-only, so make them writable first).
        # Drop once fixed upstream in nixpkgs.
        kilo = uprev.kilo.overrideAttrs (old: {
          nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ ufinal.nodejs ];
          postConfigure = (old.postConfigure or "") + ''
            chmod -R u+w packages node_modules
            patchShebangs packages/*/node_modules node_modules
          '';
          # The build's models smoke test runs the freshly-built binary as
          # `kilo --pure models anthropic`, which hangs forever in the network-
          # less build sandbox. The models sidecar snapshot is already copied
          # into the binary before this, so the test is pure build-time
          # validation — skip just that call (the --version smoke test stays).
          postPatch = (old.postPatch or "") + ''
            substituteInPlace packages/opencode/script/build.ts \
              --replace-fail 'await smokeModels(binaryPath)' \
                             'console.log("skipped models smoke test (nix sandbox)")'
          '';
        });
      });
  };
}
