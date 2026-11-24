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

  # Build a lazy package scope that injects -march/-mtune (C/C++), target-cpu
  # (Rust/Crane), GOAMD64 (Go), and opportunistic Icecream distributed C/C++
  # compilation (via /run/icecc/iceccd.socket when active) ONLY into derivations
  # explicitly pulled from the scope (pkgs.cpuTune.<pkg> or pkgs.groupTune.<pkg>),
  # avoiding global stdenv / reverse-dependency rebuild cascades.
  # When arch is null/empty (or when cross-compiling), returns `pkgs` unchanged
  # so unconfigured hosts hit cache.nixos.org 100%.
  mkTunedScopeWith = rootPkgs: pkgs: arch:
    let
      lib = pkgs.lib;
      isNative = pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform;
      isX86_64 = pkgs.stdenv.hostPlatform.isx86_64;

      goAmd64 =
        if !isX86_64 then null
        else if builtins.elem arch [ "x86-64-v4" "znver4" "znver5" "icelake-client" "icelake-server" "sapphirerapids" ] then "v4"
        else if builtins.elem arch [ "x86-64-v3" "haswell" "broadwell" "skylake" "alderlake" "raptorlake" "znver1" "znver2" "znver3" ] then "v3"
        else if builtins.elem arch [ "x86-64-v2" "nehalem" "westmere" "sandybridge" "ivybridge" ] then "v2"
        else "v1";

      icecreamPkg = rootPkgs.icecream;
      ccachePkg = rootPkgs.ccache;
      unwrappedGCC = pkgs.stdenv.cc.cc;

      # Pure Nix-built Icecream compiler environment archive (<md5>.tar.zst) for
      # this stdenv's exact unwrapped GCC/G++, shipped by iceccd to remote peers.
      iceccEnv = pkgs.runCommand "icecc-env-${unwrappedGCC.version}" { } ''
        mkdir -p "$out"
        cd "$out"
        "${icecreamPkg}/bin/icecc-create-env" \
          --gcc "${unwrappedGCC}/bin/gcc" "${unwrappedGCC}/bin/g++" \
          --compression zstd
        tarfile=$(ls *.tar.zst)
        ln -s "$tarfile" env.tar.zst
      '';

      # Mirror nixpkgs' ccache.links / ccacheStdenv pattern: stdenv.cc (cc-wrapper)
      # expands all /nix/store header/lib paths + -march flags first, then invokes
      # our inner wrapper:
      #   1. Two-tier ccache (local /var/cache/ccache L1 + fleet wt0 Valkey L2 via
      #      /run/ccache/l2.sock when /run/ccache/online is present).
      #   2. On ccache miss, CCACHE_PREFIX dispatches over /run/icecc/iceccd.socket
      #      when local icecc-daemon is up, or falls back to unwrapped GCC.
      iceccLinks = pkgs.stdenv.mkDerivation {
        pname = "icecc-links";
        inherit (unwrappedGCC) version;
        passthru = {
          isClang = unwrappedGCC.isClang or false;
          isGNU = unwrappedGCC.isGNU or false;
          isCcache = true;
        } // builtins.intersectAttrs {
          hardeningUnsupportedFlagsByTargetPlatform = null;
          hardeningUnsupportedFlags = null;
        } unwrappedGCC;
        lib = lib.getLib unwrappedGCC;
        buildCommand =
          let
            targetPrefix =
              if unwrappedGCC.isClang or false then ""
              else lib.optionalString (
                unwrappedGCC ? targetConfig && unwrappedGCC.targetConfig != null && unwrappedGCC.targetConfig != ""
              ) "${unwrappedGCC.targetConfig}-";
          in
          ''
            mkdir -p "$out/bin" "$out/libexec"

            for mode in gcc g++; do
              cat > "$out/libexec/icecc-prefix-$mode" <<EOF
            #!${pkgs.runtimeShell}
            real_cc="\$1"
            shift
            if [ -S /run/icecc/iceccd.socket ]; then
              export ICECC_VERSION="${iceccEnv}/env.tar.zst"
              export ICECC_TEST_SOCKET="/run/icecc/iceccd.socket"
              export ICECC_CC="\$real_cc"
              export ICECC_CXX="\$real_cc"
              exec "${icecreamPkg}/bin/icecc" "$mode" "\$@"
            fi
            exec "\$real_cc" "\$@"
            EOF
              chmod +x "$out/libexec/icecc-prefix-$mode"
            done

            wrapCompiler() {
              local short="$1"
              local mode="$2" # "gcc" or "g++"
              local cname="${targetPrefix}$short"
              if [ -x "${unwrappedGCC}/bin/$cname" ]; then
                cat > "$out/bin/$cname" <<EOF
            #!${pkgs.runtimeShell}
            if [ -d /var/cache/ccache ] && [ -w /var/cache/ccache ]; then
              export CCACHE_DIR="/var/cache/ccache"
              export CCACHE_UMASK="002"
              export CCACHE_BASEDIR="/build"
              export CCACHE_NOHASHDIR="1"
              export CCACHE_SLOPPINESS="include_file_mtime,include_file_ctime,random_seed"
              export CCACHE_COMPILERCHECK="string:${unwrappedGCC.outPath}"
              export CCACHE_MAXSIZE="20G"
              export CCACHE_COMPRESS="1"
              export CCACHE_PREFIX="$out/libexec/icecc-prefix-$mode"
              if [ -S /run/ccache/l2.sock ] && [ -e /run/ccache/online ]; then
                export CCACHE_REMOTE_STORAGE="redis+unix:///run/ccache/l2.sock request-timeout=2s data-timeout=3s"
                export CCACHE_RESHARE="1"
              fi
              exec "${ccachePkg}/bin/ccache" "${unwrappedGCC}/bin/$cname" "\$@"
            fi
            exec "$out/libexec/icecc-prefix-$mode" "${unwrappedGCC}/bin/$cname" "\$@"
            EOF
                chmod +x "$out/bin/$cname"
              fi
            }

            wrapCompiler cc  gcc
            wrapCompiler gcc gcc
            wrapCompiler c++ g++
            wrapCompiler g++ g++

            for executable in $(ls "${unwrappedGCC}/bin"); do
              if [ ! -x "$out/bin/$executable" ]; then
                ln -s "${unwrappedGCC}/bin/$executable" "$out/bin/$executable"
              fi
            done
            for file in $(ls "${unwrappedGCC}" | grep -vw bin); do
              ln -s "${unwrappedGCC}/$file" "$out/$file"
            done
          '';
      };

      iceccStdenv = pkgs.overrideCC pkgs.stdenv (pkgs.stdenv.cc.override {
        cc = iceccLinks;
      });

      tunePkg = pkg:
        if !(lib.isDerivation pkg) || !(pkg ? overrideAttrs) then pkg
        else
          let
            canUseIceccStdenv =
              isX86_64
              && (pkgs.stdenv.cc.isGNU or false)
              && (pkg ? override)
              && ((builtins.tryEval (lib.functionArgs pkg.override)).value ? stdenv)
              && !(pkg.cudaSupport or false);
            basePkg =
              if canUseIceccStdenv
              then pkg.override { stdenv = iceccStdenv; }
              else pkg;
            tuned = basePkg.overrideAttrs (old:
              let
                # Note: in GCC/Clang, `-march=<cpu>` automatically implies `-mtune=<cpu>`
                # for concrete CPUs (znver3, raptorlake, core2, ...) and `-mtune=generic`
                # for psABI tiers (x86-64-v2, x86-64-v3), where `-mtune=x86-64-v3` is invalid.
                cflag = "-march=${arch}";
                rustflag = "-C target-cpu=${arch}";
                hasEnv = old ? env;
                oldC =
                  if hasEnv && (old.env ? NIX_CFLAGS_COMPILE) then toString old.env.NIX_CFLAGS_COMPILE
                  else if old ? NIX_CFLAGS_COMPILE then toString old.NIX_CFLAGS_COMPILE
                  else "";
                oldRust =
                  if hasEnv && (old.env ? CARGO_BUILD_RUSTFLAGS) then toString old.env.CARGO_BUILD_RUSTFLAGS
                  else if old ? CARGO_BUILD_RUSTFLAGS then toString old.CARGO_BUILD_RUSTFLAGS
                  else "";
                newC = lib.trim "${oldC} ${cflag}";
                newRust = lib.trim "${oldRust} ${rustflag}";
                envPatch =
                  if hasEnv then {
                    env = old.env // {
                      NIX_CFLAGS_COMPILE = newC;
                      CARGO_BUILD_RUSTFLAGS = newRust;
                    } // lib.optionalAttrs (goAmd64 != null) {
                      GOAMD64 = goAmd64;
                    };
                  } else {
                    NIX_CFLAGS_COMPILE = newC;
                    CARGO_BUILD_RUSTFLAGS = newRust;
                  } // lib.optionalAttrs (goAmd64 != null) {
                    GOAMD64 = goAmd64;
                  };
                cranePatch = lib.optionalAttrs (old ? cargoArtifacts && lib.isDerivation old.cargoArtifacts) {
                  cargoArtifacts = tunePkg old.cargoArtifacts;
                };
                # Dynamic online-host compile scaling + local link/load throttling:
                #   1. CMake + Ninja: size `compile` to `/run/icecc/online-cores` (when
                #      using `iceccStdenv` and local `iceccd` is up) while keeping `link=2`
                #      so concurrent `ld` invocations never blow up RAM.
                #   2. Icecream-capable builds (`canUseIceccStdenv`): scale `NIX_BUILD_CORES`
                #      at runtime to `/run/icecc/online-cores` (clamped to local GiB RAM by
                #      `distributed-compile-probe`), and pass `-l <localCores>` to GNU Make
                #      builds so local link/preprocess load stays bounded.
                #   3. Non-icecc builds (e.g. Rust, CUDA): keep `NIX_BUILD_CORES` at local `cores`.
                parallelPoolPatch = {
                  preConfigure = ''
                    if [ -z "''${dontUseCmakeConfigure:-}" ] && command -v ninja >/dev/null 2>&1 && [ -z "''${dontUseNinjaBuild:-}" ]; then
                      ${lib.optionalString canUseIceccStdenv ''
                        _icecc_cores="''${NIX_BUILD_CORES:-2}"
                        if [ -S /run/icecc/iceccd.socket ] && [ -r /run/icecc/online-cores ]; then
                          read -r _online < /run/icecc/online-cores || true
                          if [[ "''${_online:-}" =~ ^[0-9]+$ ]] && [ "$_online" -gt "$_icecc_cores" ]; then
                            _icecc_cores="$_online"
                          fi
                        fi
                        prependToVar cmakeFlags "-DCMAKE_JOB_POOLS:STRING=compile=''${_icecc_cores};link=2"
                        prependToVar cmakeFlags "-DCMAKE_JOB_POOL_COMPILE:STRING=compile"
                      ''}${lib.optionalString (!canUseIceccStdenv) ''
                        prependToVar cmakeFlags "-DCMAKE_JOB_POOLS:STRING=link=2"
                      ''}
                      prependToVar cmakeFlags "-DCMAKE_JOB_POOL_LINK:STRING=link"
                    fi
                  '' + (old.preConfigure or "");
                } // lib.optionalAttrs canUseIceccStdenv {
                  preBuild = ''
                    if [ -S /run/icecc/iceccd.socket ] && [ -r /run/icecc/online-cores ] && [ "''${enableParallelBuilding:-1}" = "1" ]; then
                      _local_cores="''${NIX_BUILD_CORES:-2}"
                      read -r _online_cores < /run/icecc/online-cores || true
                      if [[ "''${_online_cores:-}" =~ ^[0-9]+$ ]] && [ "$_online_cores" -gt "$_local_cores" ]; then
                        export NIX_BUILD_CORES="$_online_cores"
                        if ! [ -f build.ninja ] || [ -n "''${dontUseNinjaBuild:-}" ]; then
                          prependToVar makeFlags "-l ''${_local_cores}"
                        fi
                      fi
                    fi
                  '' + (old.preBuild or "");
                };
              in
              envPatch // cranePatch // parallelPoolPatch
            );
          in
          if pkg ? override then
            tuned // {
              override = args: tunePkg (pkg.override args);
            }
          else tuned;

      specialRecipes = {
        # Tune an arbitrary external derivation (e.g. flake input packages like polystack).
        tune = tunePkg;

        # Propagate tuning into pkgs.unstable when accessed as pkgs.{cpuTune,groupTune}.unstable.<pkg>.
        unstable = mkTunedScopeWith rootPkgs pkgs.unstable arch;

        # mpv is a symlinkJoin wrapper around mpv-unwrapped.
        mpv = pkgs.mpv.override {
          mpv-unwrapped = tunePkg pkgs.mpv-unwrapped;
        };

        # retroarch-full is a symlinkJoin wrapper around retroarch-bare + libretro
        # cores. Tune retroarch-bare and all fast cores, while keeping giant
        # libretro-mame* cores on cache.nixos.org.
        retroarch-full =
          let
            tunedBare = tunePkg pkgs.retroarch-bare;
            tunedWrapper = (tunedBare.override { retroarch-bare = tunedBare; }).wrapper { };
          in
          tunedWrapper.withCores (cores:
            map
              (c: if lib.hasInfix "mame" c.name then c else tunePkg c)
              (lib.filter (c:
                (c ? libretroCore)
                && (lib.meta.availableOn pkgs.stdenv.hostPlatform c)
                && !(lib.hasInfix "fbalpha2012" c.name)
              ) (lib.attrValues cores))
          );
      };
    in
    if arch == null || arch == "" || !isNative
    then pkgs
    else (lib.mapAttrs (_: v: tunePkg v) pkgs) // specialRecipes;
in {
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: prev: {
    # Polygon node stack (butthead bor-node.nix): upstream release binaries.
    bor = final.callPackage ../pkgs/bor { };
    heimdall-v2 = final.callPackage ../pkgs/heimdall-v2 { };

    # LazyPi — opinionated one-shot installer that sets up the Pi coding agent
    # with a curated catalog of extensions, skills, prompt templates, and themes
    # (sub-agents, MCP, web access, memory, plan, diff review, powerbar, usage
    # dashboard, themes, …). Installed alongside pi-coding-agent so the
    # home-manager pi-agent module can deploy that catalog declaratively AND
    # offer the `lazypi` CLI (status/doctor/update/remove). See pkgs/lazypi/.
    lazypi = final.callPackage ../pkgs/lazypi { };

    # kimi-cli — Moonshot AI's Kimi Code CLI (PyPI: kimi-cli), command `kimi`.
    # A standalone terminal coding agent, AND the credential source the
    # pi-kimi-coder extension auto-imports (reads ~/.kimi/credentials/). Bundles
    # four deps nixpkgs lacks (kosong/pykaos/streamingjson/ripgrepy). See
    # pkgs/kimi-cli/. Not packaged in nixpkgs, so we build our vendored
    # expression against the UNSTABLE package set (python deps move fast;
    # the wheel version itself is still pinned manually in pkgs/kimi-cli).
    kimi-cli = final.unstable.callPackage ../pkgs/kimi-cli { };

    # Xilinx forks for the MYIR Z-turn (Zynq-7020). Cross-compile when the
    # consuming config is armv7l (z-turn). See pkgs/zynq/.
    ubootZturn = final.callPackage ../pkgs/zynq/uboot.nix { };
    linuxZynqXlnx = final.callPackage ../pkgs/zynq/kernel.nix { };

    # Xilinx fork for the AMD/Xilinx KR260 (Zynq UltraScale+ ZU2EG, aarch64).
    # Cross-compile when the consuming config is aarch64 built on x86 (kr260).
    # Reuses the same linux-xlnx tree/rev as the Zynq-7000 kernel (one FOD).
    linuxZynqmpXlnx = final.callPackage ../pkgs/zynq/kernel-zynqmp.nix { };

    # load-fpga: program a Zynq/ZynqMP PL over the network from any local path,
    # via the Linux fpga-manager — no JTAG, no /nix/store writes. Points the
    # firmware loader at /tmp (writable, unlike the store) through the
    # firmware_class.path param, copies the bitstream there, then triggers the
    # manager. The image must already be fpga-manager format (.bit.bin), as
    # produced by: bootgen -image bitswap.bif -arch {zynq|zynqmp} -process_bitstream bin
    load-fpga = final.writeShellScriptBin "load-fpga" ''
      set -euo pipefail
      if [ "$#" -ne 1 ]; then
        echo "usage: load-fpga <bitstream.bit.bin>" >&2
        exit 2
      fi
      src="$1"
      name="$(basename "$src")"
      fw_param="/sys/module/firmware_class/parameters/path"
      mgr="/sys/class/fpga_manager/fpga0"
      [ -e "$fw_param" ] || { echo "load-fpga: $fw_param missing (firmware_class not loaded?)" >&2; exit 1; }
      [ -d "$mgr" ]      || { echo "load-fpga: $mgr missing (fpga-manager driver not probed?)" >&2; exit 1; }
      # Redirect the firmware loader at a writable dir; store search path is RO.
      echo -n "/tmp" | sudo tee "$fw_param" >/dev/null
      cp "$src" "/tmp/$name"
      echo "$name" | sudo tee "$mgr/firmware" >/dev/null
      state="$(cat "$mgr/state")"
      echo "load-fpga: $name -> fpga0 state=$state"
    '';
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

    # fastfetch defaults to pulling a heavy media/GUI stack via its optional
    # image support (imagemagick, chafa) and Enlightenment support
    # (efl -> ffmpeg -> openapv, chromaprint). None of that is needed to print
    # system info; disabling it keeps the closure lean on every host and stops
    # headless/work boxes (devdesktop/gravidesktop) from dragging in ffmpeg.
    fastfetch = prev.fastfetch.override {
      imageSupport = false;
      enlightenmentSupport = false;
    };

    # fish 4.x doesn't cross-compile: its man-page doc-gen step (`cargo xtask
    # man-pages`) builds the `xtask` helper, whose pcre2 dependency links the
    # TARGET (armv7l) pcre2 while xtask is compiled for the build platform (x86)
    # — the linker rejects the incompatible lib. Skip man-page generation on
    # cross only (force SPHINX "not found", which gates the man-pages target).
    # The fish binary, functions, and runtime completions are unaffected; native
    # hosts keep their man pages. This lets fish build for the armv7l z-turn.
    fish =
      if prev.stdenv.buildPlatform == prev.stdenv.hostPlatform
      then prev.fish
      else prev.fish.overrideAttrs (old: {
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DSPHINX_EXECUTABLE=SPHINX_EXECUTABLE-NOTFOUND" ];
      });

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

    # libJudy's JudySLIns does strcpy patterns that glibc 2.42 + _FORTIFY_SOURCE=3
    # (nixpkgs' default hardening) flags as an overflow, so __strcpy_chk aborts
    # the caller. This crashes gtkwave the moment it builds a VCD's symbol table
    # with real (multi-char) signal names: vcd_build_symbols → symadd → JudySLIns
    # → "*** buffer overflow detected ***: terminated" (SIGABRT). Disable fortify
    # on judy so gtkwave — which links libJudy.so.1 — stops aborting. Drop if
    # nixpkgs/judy upstream gains a fortify3-safe fix.
    judy = prev.judy.overrideAttrs (old: {
      hardeningDisable = (old.hardeningDisable or [ ]) ++ [ "fortify" "fortify3" ];
    });

    # ccextractor 0.94-unstable-2025-05-20 doesn't build against gpac 26.07:
    # gpac's setup.h now poisons strcpy/strcat/strncpy/strncat with #error
    # unless GPAC_ALLOW_UNSAFE_STRFUNC is defined before including its headers
    # ("stray '#' in program" in lib_ccx/mp4.c). Define it — ccextractor only
    # uses these on its own buffers, not gpac's. Drop when nixpkgs' ccextractor
    # bump fixes gpac 26.07 compat upstream.
    ccextractor = prev.ccextractor.overrideAttrs (old: {
      env = (old.env or { }) // {
        NIX_CFLAGS_COMPILE = (old.env.NIX_CFLAGS_COMPILE or "") + " -DGPAC_ALLOW_UNSAFE_STRFUNC";
      };
    });

    # gt (git tracker) has an ancient cmake_minimum_required that CMake 4.x
    # rejects outright. Bump the policy floor so it configures. This affects
    # cross builds (adbd depends on it) and may affect native builds too.
    gt = prev.gt.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
    });

    # mobile-nixos' gadget-tool (USB gadget enabler) is the same upstream `gt`
    # source but lives under the `gadget-tool` attribute. Fix its CMake floor too.
    gadget-tool =
      if prev ? gadget-tool
      then prev.gadget-tool.overrideAttrs (old: {
        cmakeFlags = (old.cmakeFlags or [ ]) ++ [ "-DCMAKE_POLICY_VERSION_MINIMUM=3.5" ];
      })
      else { };

    # Local bcachefs patches on top of nixpkgs' bcachefs-tools (1.39.7; the
    # out-of-tree kernel module linuxPackages.*.bcachefs builds from
    # bcachefs-tools.dkms so it inherits these patches automatically).
    # Rationale & upstream audit in bcachefs-patchz.md:
    #   - Patch C (device-remove-dead-stripes): reap degraded+empty stripes in
    #     bch2_stripe_repair() and wake/pace reconcile during device removal.
    #   - Patch F (ec-bound-stripe-reuse): filter mismatched label/algo/redundancy
    #     early in get_old_stripe() and bound stripe_reuse() LRU scans (128/512).
    #   - Patch G (copygc-data-update-durability-livelock): compute whole-key
    #     deduplicated online durability in bch2_bkey_durability_keeping() so
    #     copygc does not livelock on shared-device EC+replica extents, fix
    #     move.c no-op sectors_seen counting, and fix copygc.c EC stripe copygc
    #     (ret2=1 positive return abort, can_widen full-stripe head, and
    #     bucket_frag_ratio==0).
    # Former Patches A & E were merged upstream in 1.39.7 (468334a60a, f820d39953)
    # and dropped along with the 1.39.6 pin.
    bcachefs-tools = prev.bcachefs-tools.overrideAttrs (old: {
      patches = (old.patches or [ ]) ++ [
        ./patches/bcachefs-device-remove-dead-stripes.patch
        ./patches/bcachefs-ec-bound-stripe-reuse.patch
        ./patches/bcachefs-copygc-data-update-durability-livelock.patch
        ./patches/bcachefs-linux-6.18.64-inode-state.patch
      ];
    });

    # whipper 0.10.0 imports pkg_resources in 4 modules, but setuptools 81+
    # (nixpkgs-unstable ships 82) removed pkg_resources entirely. Patch the
    # imports to use stdlib importlib.metadata and packaging instead, add
    # packaging as a runtime dep, and skip the test suite (which also fails on
    # the missing import). Drop when fixed upstream in nixpkgs.
    whipper = prev.whipper.overridePythonAttrs (old: {
      propagatedBuildInputs = (old.propagatedBuildInputs or [ ]) ++ [
        prev.python3Packages.packaging
      ];
      patches = (old.patches or [ ]) ++ [
        ./patches/whipper-pkg-resources.patch
      ];
      doInstallCheck = false;
    });

    # SDRplay removed 3.15.1 from www.sdrplay.com/software/ (404), and sdrplay is
    # unfree so cache.nixos.org does not mirror the installer. Add the
    # Archive.org snapshot (identical hash/FOD name) so uncached builds succeed.
    sdrplay = prev.sdrplay.overrideAttrs (old: {
      src = prev.fetchurl {
        inherit (old.src) name;
        urls = [
          "https://www.sdrplay.com/software/SDRplay_RSP_API-Linux-${old.version}.run"
          "https://web.archive.org/web/20260116000508if_/https://www.sdrplay.com/software/SDRplay_RSP_API-Linux-${old.version}.run"
        ];
        hash = old.src.outputHash;
      };
    });

    # Upstream icecream's icecc-create-env hardcodes FHS paths (/usr/bin/md5sum,
    # /bin/true) that don't exist on NixOS, producing an unverified ".tar.zst"
    # with an empty MD5 prefix. Patch in coreutils + runtime tool PATH.
    icecream = prev.icecream.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.makeWrapper ];
      postPatch = (old.postPatch or "") + ''
        # Upstream bug: after accept() sets `next_listen = time(nullptr) + 1`, if
        # a connection closes within the same second, listen_fd is omitted from
        # pollfds while `timeout` can be 3600s, wedging accept() for up to an hour.
        substituteInPlace scheduler/scheduler.cpp \
          --replace-fail 'if (time(nullptr) >= next_listen) {' \
            'if (time(nullptr) < next_listen && timeout > 1) timeout = 1; if (time(nullptr) >= next_listen) {'
      '';
      postFixup = (old.postFixup or "") + ''
        substituteInPlace "$out/bin/icecc-create-env" \
          --replace-fail 'for file in /usr/bin/md5sum' 'for file in ${prev.coreutils}/bin/md5sum /usr/bin/md5sum' \
          --replace-fail 'if test -x /bin/true; then' 'if test -x ${prev.coreutils}/bin/true; then' \
          --replace-fail 'add_file /bin/true' 'add_file ${prev.coreutils}/bin/true /bin/true'
        wrapProgram "$out/bin/icecc-create-env" \
          --prefix PATH : "${prev.lib.makeBinPath (with prev; [
            coreutils gnutar zstd gzip bzip2 xz file findutils gnused gnugrep gawk glibc.bin
          ])}"
      '';
    });

    # sccache built with distributed client + scheduler + build-server support.
    sccache-dist = prev.sccache.override { distributed = true; };

    # Baseline no-op tuning scopes (overridden per NixOS host by
    # flake-modules/system/cpu-tune.nix when hardware.cpu.tune.{cpu,group} is set).
    # Unconfigured hosts, cross-compiled targets, and standalone Home Manager
    # configs default to stock x86_64-linux / cache.nixos.org.
    tune = prev.tune or (x: x);
    mkTunedScope = mkTunedScopeWith final final;
    cpuTune = prev.cpuTune or final;
    groupTune = prev.groupTune or final;
  };

  # Force every buildGo*Module vendor fetch through GOPROXY=direct / GOSUMDB=off.
  #
  # This is applied ONLY on corp machines (devdesktop, gravidesktop, work-laptop),
  # NOT globally: that network sinkholes proxy.golang.org and sum.golang.org (the
  # TLS cert served is for chalupa-dns-sinkhole.corp.amazon.com), so the default
  # GOPROXY can't fetch module zips — every `*-go-modules` fixed-output
  # derivation fails (e.g. sops-nix's sops-install-secrets). GOPROXY=direct
  # fetches modules straight from their VCS (github etc.), which IS reachable;
  # GOSUMDB=off skips the equally-sinkholed checksum database. Integrity is still
  # guaranteed by Nix's vendorHash, so disabling the sumdb is safe.
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
        build = final.stdenv.buildPlatform.system;
        host = final.stdenv.hostPlatform.system;
        # Cross hosts (z-turn/kr260/phones): import unstable as a CROSS set
        # (build on x86, target the host arch). A plain `system = host` makes
        # a *native* target set whose stdenv needs target bootstrap-tools —
        # which no builder can run (observed: pkgs.unstable.atuin on armv7l
        # pulling in bootstrap-tools.drv → "platform mismatch").
        platformArgs =
          if build == host
          then { system = host; }
          else { localSystem = build; crossSystem = host; };
      in
      (import inputs.nixpkgs-unstable ({
        config.allowUnfree = true;
      } // platformArgs)).extend (ufinal: uprev: {
        # atuin links openssl (via sqlx/native-tls). Cross-compiling builds its
        # proc-macros (sqlx-macros) for the BUILD machine, which then can't
        # find -lssl/-lcrypto (openssl is only in host buildInputs). Give the
        # build machine its own openssl. See the platformArgs note above —
        # this only bites on cross hosts (phones, z-turn, kr260).
        atuin =
          if ufinal.stdenv.buildPlatform != ufinal.stdenv.hostPlatform
          then uprev.atuin.overrideAttrs (old: {
            depsBuildBuild = (old.depsBuildBuild or [ ]) ++ [ ufinal.buildPackages.openssl ];
            # Point openssl-sys (in sqlx' build-time proc-macros) at the BUILD
            # machine's openssl. MUST be target-prefixed: unprefixed
            # OPENSSL_LIB_DIR also poisons the host link (armv7 atuin-server
            # tried to link the x86 libssl). Host-target linking uses the host
            # openssl via buildInputs/pkg-config.
            env = (old.env or { }) // {
              X86_64_UNKNOWN_LINUX_GNU_OPENSSL_DIR = "${ufinal.buildPackages.openssl.dev}";
              X86_64_UNKNOWN_LINUX_GNU_OPENSSL_LIB_DIR = "${ufinal.buildPackages.openssl.out}/lib";
              X86_64_UNKNOWN_LINUX_GNU_OPENSSL_INCLUDE_DIR = "${ufinal.buildPackages.openssl.dev}/include";
              OPENSSL_NO_VENDOR = "1";
            };
          })
          else uprev.atuin;

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
