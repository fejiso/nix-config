{ ... }: {
  flake.modules.nixos.cli = { config, lib, ... }:
    let
      cfg = config.hardware.cpu.tune;
      effectiveCpu = if cfg.cpu != null then cfg.cpu else cfg.group;
      hasTuning = cfg.cpu != null || cfg.group != null;
    in
    {
      # Two-tier opt-in microarchitecture tuning (see overlays/default.nix `mkTunedScope`):
      #   - `group` -> `pkgs.groupTune.<pkg>`: shared ISA bucket across fleet peers so
      #     hierro's nix-builder builds media, emulation, SDR, polystack, bcachefs-tools,
      #     FPGA, and pentest binaries once per tier:
      #       * "x86-64-v3" (AVX2+FMA+BMI2): butthead, tungsten, hierro, blacktop, elitedex, lenovix
      #       * "x86-64-v2" (SSE4.2+POPCNT): hispanas (i3-3220), snuffles (N3060), a8 (A8-7410)
      #       * "core2"     (SSSE3):         Core 2 Quad Q6600, Core 2 Duo SU7300
      #   - `cpu`   -> `pkgs.cpuTune.<pkg>`: exact chip microarch for LLM/llama.cpp hot
      #     kernels ("raptorlake" on tungsten, "znver3" on butthead, "znver2" on
      #     hierro/blacktop, "znver1" on elitedex, "skylake" on lenovix, "ivybridge" on
      #     hispanas, "silvermont" on snuffles, "btver2" on a8, "core2" on Q6600,
      #     "penryn" on SU7300).
      #   - Hosts that omit `hardware.cpu.tune` keep both null -> stock x86_64-linux /
      #     native platform with 100% cache.nixos.org binary cache hits.
      options.hardware.cpu.tune = {
        cpu = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "raptorlake";
          description = "Exact GCC/LLVM -march/-mtune target for pkgs.cpuTune (falls back to group, then stock pkgs).";
        };

        group = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          example = "x86-64-v3";
          description = "Shared ISA tier for pkgs.groupTune (falls back to stock pkgs / cache.nixos.org when null).";
        };
      };

      config = lib.mkIf hasTuning {
        # Order 2000 ensures this always runs after base.nix's mkAfter (1500) overlays.
        nixpkgs.overlays = lib.mkOrder 2000 [
          (final: _prev: {
            groupTune = final.mkTunedScope cfg.group;
            cpuTune = final.mkTunedScope effectiveCpu;
          })
        ];
      };
    };
}
