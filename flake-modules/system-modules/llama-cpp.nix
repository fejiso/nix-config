{ ... }: {
  flake.modules.nixos.llama-cpp =
    { config, lib, pkgs, hostname, ... }:

    with lib;

    let
      cfg = config.services.llama-cpp;
      tuneCfg = config.hardware.cpu.tune;
      effectiveCpu = if tuneCfg.cpu != null then tuneCfg.cpu else tuneCfg.group;

      backendFlags = {
        none = { };
        cuda = { cudaSupport = true; };
        rocm = { rocmSupport = true; };
        vulkan = { vulkanSupport = true; };
      };

      # Strip HuggingFace `.gguf_file` suffixes (used by Unsloth's Mainline_Support
      # folder so tools don't mix layouts) down to `.gguf` on disk.
      ggufNameOf = url: removeSuffix "_file" (baseNameOf url);

      modelFile = "${cfg.modelsDir}/${ggufNameOf cfg.modelUrl}";
      mmprojFile = optionalString (cfg.mmprojUrl != null) "${cfg.modelsDir}/${ggufNameOf cfg.mmprojUrl}";
      draftFile = optionalString (cfg.draftModelUrl != null) "${cfg.modelsDir}/${ggufNameOf cfg.draftModelUrl}";

      effectiveAlias = if cfg.alias != null then cfg.alias else "inkling-2-mini-${hostname}";

      # CPU builds pull from pkgs.cpuTune.unstable (exact -march + icecc/ccache).
      # GPU/CUDA builds use cudaPackages.backendStdenv directly so NIX_BUILD_CORES
      # stays bounded to local cores (preventing 60-way nvcc OOMs), while still
      # applying host -march tuning for CPU-offloaded MoE kernels and narrowing
      # CMAKE_CUDA_ARCHITECTURES to the host's exact SM when cudaArch is set.
      llamaPackage =
        if cfg.gpuBackend == "none" then
          pkgs.cpuTune.unstable.llama-cpp.override {
            cpuArchDynamicDispatch = false;
          }
        else
          let
            gpuBase = pkgs.unstable.llama-cpp.override (
              { cpuArchDynamicDispatch = false; } // backendFlags.${cfg.gpuBackend}
            );
          in
          gpuBase.overrideAttrs (old:
            let
              hasEnv = old ? env;
              oldC =
                if hasEnv && (old.env ? NIX_CFLAGS_COMPILE) then toString old.env.NIX_CFLAGS_COMPILE
                else if old ? NIX_CFLAGS_COMPILE then toString old.NIX_CFLAGS_COMPILE
                else "";
              newC =
                if effectiveCpu != null
                then lib.trim "${oldC} -march=${effectiveCpu}"
                else oldC;
              envAttrs =
                if effectiveCpu == null then { }
                else if hasEnv then { env = old.env // { NIX_CFLAGS_COMPILE = newC; }; }
                else { NIX_CFLAGS_COMPILE = newC; };
              baseCmake =
                if cfg.gpuBackend == "cuda" && cfg.cudaArch != null
                then filter (f: !(hasInfix "CMAKE_CUDA_ARCHITECTURES" f)) (old.cmakeFlags or [ ])
                  ++ [ (lib.cmakeFeature "CMAKE_CUDA_ARCHITECTURES" cfg.cudaArch) ]
                else (old.cmakeFlags or [ ]);
            in
            envAttrs // {
              cmakeFlags = baseCmake ++ [
                "-DCMAKE_JOB_POOLS:STRING=link=2"
                "-DCMAKE_JOB_POOL_LINK:STRING=link"
              ];
            }
          );

      fetchItems =
        [ { url = cfg.modelUrl; dest = modelFile; } ]
        ++ optional (cfg.mmprojUrl != null) { url = cfg.mmprojUrl; dest = mmprojFile; }
        ++ optional (cfg.draftModelUrl != null) { url = cfg.draftModelUrl; dest = draftFile; };

      serverArgs =
        [
          "${llamaPackage}/bin/llama-server"
          "--model" modelFile
          "--alias" effectiveAlias
          "--host" "0.0.0.0"
          "--port" (toString cfg.port)
          "--parallel" (toString cfg.parallel)
          "--ctx-size" (toString cfg.ctxSize)
          "-ctk" cfg.cacheTypeK
          "-ctv" cfg.cacheTypeV
          "--jinja"
          "-fa" "on"
          "--temp" "1.0"
          "--top-p" "1.0"
          "--top-k" "0"
          "--min-p" "0.0"
        ]
        ++ optionals (cfg.threads != null) [
          "--threads" (toString cfg.threads)
          "--threads-batch" (toString (if cfg.threadsBatch != null then cfg.threadsBatch else cfg.threads))
        ]
        ++ optionals (cfg.mmprojUrl != null) [
          "--mmproj" mmprojFile
        ]
        ++ optionals (cfg.draftModelUrl != null) (
          [ "--model-draft" draftFile ]
          ++ optionals (cfg.specType != null) [ "--spec-type" cfg.specType ]
          ++ optionals (cfg.specDraftMax != null) [ "--spec-draft-n-max" (toString cfg.specDraftMax) ]
          ++ optionals cfg.specProbabilistic [ "--spec-draft-sampling" "probabilistic" ]
        )
        ++ optionals (cfg.gpuBackend != "none") (
          optionals cfg.fit [ "--fit" "on" "--fit-target" (toString cfg.fitTargetMiB) ]
          ++ optionals (!cfg.fit) [ "--fit" "off" ]
          # Note: leave nGpuLayers = null and tensorOverrides = [ ] when fit = true!
          # Passing explicit -ngl or -ot aborts common_params_fit_impl, which
          # otherwise places 100% of dense attention/KV in dedicated GDDR6 VRAM,
          # spills excess MoE expert tensors to system RAM, and promotes as many
          # MoE layers into physical VRAM as fit within fitTargetMiB.
          ++ optionals (cfg.nGpuLayers != null) [ "-ngl" (toString cfg.nGpuLayers) ]
          ++ concatMap (ov: [ "-ot" ov ]) cfg.tensorOverrides
        )
        ++ cfg.extraArgs;
    in
    {
      disabledModules = [ "services/misc/llama-cpp.nix" ];

      options.services.llama-cpp = {
        enable = mkEnableOption "local llama.cpp inference server (llama-server)";

        port = mkOption {
          type = types.port;
          default = 8079;
          description = "HTTP API port for llama-server (exposed on loopback and NetBird wt0)";
        };

        alias = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "inkling-2-mini-butthead";
          description = "Model ID advertised by /v1/models (defaults to inkling-2-mini-<hostname>)";
        };

        modelsDir = mkOption {
          type = types.path;
          default = "/var/lib/llama-models";
          description = "Directory where GGUF model files are stored (excluded from Kopia backups)";
        };

        modelUrl = mkOption {
          type = types.str;
          # Default to Unsloth Mainline_Support UD-Q4_K_XL on all hosts: CPU-spilled
          # MoE expert layers get repacked into 8x8 AVX2 GEMM/GEMV kernels (NVFP4 has
          # no CPU repack kernel and leaves layers 20..23 at 2x-larger Q8_0), while
          # GPU-resident layers use native CUDA MMQ/MMVQ kernels.
          default = "https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/main/Mainline_Support/Inkling-2-Mini-UD-Q4_K_XL.gguf_file";
          description = "Hugging Face resolve URL for the primary GGUF model";
        };

        mmprojUrl = mkOption {
          type = types.nullOr types.str;
          default = "https://huggingface.co/ggml-org/Inkling-2-Mini-GGUF/resolve/main/mmproj-Inkling-2-Mini-Q8_0.gguf";
          description = "Optional Hugging Face resolve URL for the multimodal vision projector (mmproj)";
        };

        draftModelUrl = mkOption {
          type = types.nullOr types.str;
          # Disabled by default when MoE experts live in CPU RAM: verifying a 6-token
          # draft batch activates ~5x as many distinct experts/layer in DDR4/DDR5
          # (~40/128 vs 8/128) and adds 500 MB VRAM + 201k-vocab drafter overhead.
          default = null;
          example = "https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/main/Mainline_Support/dspark-Inkling-2-Mini-Q8_0.gguf_file";
          description = "Optional Hugging Face resolve URL for the speculative decoding draft model";
        };

        specType = mkOption {
          type = types.nullOr types.str;
          default = "draft-dspark";
          description = "Speculative decoding draft type passed via --spec-type when draftModelUrl is set";
        };

        specDraftMax = mkOption {
          type = types.nullOr types.ints.positive;
          default = 5;
          description = "Maximum drafted tokens per step (--spec-draft-n-max)";
        };

        specProbabilistic = mkOption {
          type = types.bool;
          default = true;
          description = "Enable --spec-draft-sampling probabilistic rejection sampling for positive temperatures";
        };

        parallel = mkOption {
          type = types.ints.positive;
          default = 1;
          description = "Number of concurrent server slots (--parallel); 1 avoids 4x 48-layer recurrent conv state overhead";
        };

        ctxSize = mkOption {
          type = types.ints.positive;
          default = 65536;
          description = "Prompt context window size (--ctx-size)";
        };

        cacheTypeK = mkOption {
          type = types.str;
          default = "q8_0";
          description = "KV cache K data type (-ctk); q8_0 halves 64k KV VRAM with negligible quality impact";
        };

        cacheTypeV = mkOption {
          type = types.str;
          default = "q8_0";
          description = "KV cache V data type (-ctv); q8_0 halves 64k KV VRAM with negligible quality impact";
        };

        threads = mkOption {
          type = types.nullOr types.ints.positive;
          default = null;
          description = "CPU thread count for generation (--threads); set to physical/P-core count";
        };

        threadsBatch = mkOption {
          type = types.nullOr types.ints.positive;
          default = null;
          description = "CPU thread count for batch/prompt processing (--threads-batch); defaults to threads";
        };

        cpuAffinity = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "0-15";
          description = "Optional systemd CPUAffinity mask (e.g. '0-15' to pin hybrid Intel CPUs to P-cores)";
        };

        gpuBackend = mkOption {
          type = types.enum [ "none" "cuda" "rocm" "vulkan" ];
          default = "none";
          description = "GPU backend for llama.cpp";
        };

        cudaArch = mkOption {
          type = types.nullOr types.str;
          default = null;
          example = "86";
          description = "Target CUDA SM architecture (e.g. '86' for RTX 3060 Ampere, '89' for RTX 3500 Ada)";
        };

        cudaUnifiedMemory = mkOption {
          type = types.bool;
          # Keep OFF on discrete PCIe GPUs: cudaMallocManaged causes severe LRU
          # PCIe page-fault thrashing (~1-3 tok/s) whenever working set > VRAM,
          # and tricks --fit into reading /proc/meminfo instead of cudaMemGetInfo.
          # Use --fit on (fit = true) for explicit CPU-RAM MoE spillover instead.
          default = false;
          description = "Set GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 (only recommended on true UMA hardware)";
        };

        nGpuLayers = mkOption {
          type = types.nullOr types.int;
          default = null;
          description = "Explicit -ngl override (leave null when fit = true so llama.cpp auto-fits VRAM + CPU MoE spillover)";
        };

        fit = mkOption {
          type = types.bool;
          default = true;
          description = "Enable llama.cpp --fit on to pin dense/KV in VRAM and spill excess MoE experts to system RAM";
        };

        fitTargetMiB = mkOption {
          type = types.ints.positive;
          default = 1024;
          description = "Free physical VRAM headroom in MiB (--fit-target) reserved for desktop/containers/mmproj";
        };

        tensorOverrides = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Explicit tensor buffer placement overrides (-ot); leave empty when fit = true";
        };

        extraArgs = mkOption {
          type = types.listOf types.str;
          default = [ ];
          description = "Extra CLI arguments appended to llama-server";
        };

        extraEnvironment = mkOption {
          type = types.attrsOf types.str;
          default = { };
          description = "Extra environment variables set on llama-cpp.service";
        };
      };

      config = mkIf cfg.enable {
        systemd.services.llama-cpp-model-fetch = {
          description = "Download GGUF weights for local llama.cpp server";
          wantedBy = [ "llama-cpp.service" ];
          before = [ "llama-cpp.service" ];
          after = [ "network-online.target" ];
          wants = [ "network-online.target" ];
          serviceConfig = {
            Type = "oneshot";
            Restart = "on-failure";
            RestartSec = 15;
            ExecStart = pkgs.writeShellScript "llama-cpp-model-fetch" ''
              set -euo pipefail
              mkdir -p ${escapeShellArg cfg.modelsDir}
              ${concatMapStringsSep "\n" (item: ''
                if [ ! -s ${escapeShellArg item.dest} ]; then
                  echo "Downloading ${item.url} -> ${item.dest}"
                  ${pkgs.curl}/bin/curl -fL --retry 5 --retry-delay 5 -C - \
                    -o ${escapeShellArg "${item.dest}.part"} \
                    ${escapeShellArg item.url}
                  mv ${escapeShellArg "${item.dest}.part"} ${escapeShellArg item.dest}
                fi
              '') fetchItems}
            '';
          };
        };

        systemd.services.llama-cpp = {
          description = "llama.cpp local inference server (${effectiveAlias})";
          wantedBy = [ "multi-user.target" ];
          requires = [ "llama-cpp-model-fetch.service" ];
          after = [ "network-online.target" "netbird.service" "llama-cpp-model-fetch.service" ];
          wants = [ "network-online.target" ];
          environment =
            optionalAttrs (cfg.gpuBackend == "cuda" && cfg.cudaUnifiedMemory) {
              GGML_CUDA_ENABLE_UNIFIED_MEMORY = "1";
            }
            // cfg.extraEnvironment;
          serviceConfig = {
            # Wrap in writeShellScript rather than passing escapeShellArgs directly
            # to ExecStart: systemd's own command-line parser unescapes backslashes
            # even inside single quotes, which would mangle regex escapes.
            ExecStart = pkgs.writeShellScript "llama-cpp-start" ''
              exec ${escapeShellArgs serverArgs}
            '';
            Restart = "on-failure";
            RestartSec = 10;
            NoNewPrivileges = true;
            # GPU backends require /dev/nvidia* or /dev/dri — no DynamicUser.
          } // optionalAttrs (cfg.cpuAffinity != null) {
            CPUAffinity = cfg.cpuAffinity;
          };
        };

        # Reachable over the NetBird mesh (and loopback).
        networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.port ];
      };
    };
}
