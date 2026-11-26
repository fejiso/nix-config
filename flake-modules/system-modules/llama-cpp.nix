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
          "--ctx-size" (toString cfg.ctxSize)
          "--jinja"
          "-fa" "on"
          "--temp" "1.0"
          "--top-p" "1.0"
          "--top-k" "0"
          "--min-p" "0.0"
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
          [ "-ngl" (toString cfg.nGpuLayers) ]
          ++ optionals cfg.fit [ "--fit" "on" ]
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
          default = "https://huggingface.co/ggml-org/Inkling-2-Mini-GGUF/resolve/main/Inkling-2-Mini-NVFP4.gguf";
          description = "Hugging Face resolve URL for the primary GGUF model";
        };

        mmprojUrl = mkOption {
          type = types.nullOr types.str;
          default = "https://huggingface.co/ggml-org/Inkling-2-Mini-GGUF/resolve/main/mmproj-Inkling-2-Mini-Q8_0.gguf";
          description = "Optional Hugging Face resolve URL for the multimodal vision projector (mmproj)";
        };

        draftModelUrl = mkOption {
          type = types.nullOr types.str;
          default = "https://huggingface.co/unsloth/Inkling-2-Mini-GGUF/resolve/main/Mainline_Support/dspark-Inkling-2-Mini-Q8_0.gguf_file";
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

        ctxSize = mkOption {
          type = types.ints.positive;
          default = 65536;
          description = "Prompt context window size (--ctx-size)";
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
          default = false;
          description = ''
            Set GGML_CUDA_ENABLE_UNIFIED_MEMORY=1 so CUDA allocations spill into
            system memory via cudaMallocManaged instead of failing with OOM when
            VRAM is tight or shared with desktop/container workloads.
          '';
        };

        nGpuLayers = mkOption {
          type = types.int;
          default = 99;
          description = "Number of layers offloaded to GPU (-ngl) when gpuBackend != 'none'";
        };

        fit = mkOption {
          type = types.bool;
          default = true;
          description = "Pass --fit on to llama-server when gpuBackend != 'none'";
        };

        tensorOverrides = mkOption {
          type = types.listOf types.str;
          # Inkling 2 Mini has 24 physical layers: 0..5 and 18..23 run 1x/token,
          # while loop-core layers 6..17 run 3x/token. On 12 GB GPUs, keeping
          # loop-core MoE experts 10..17 + all 48 attention/KV passes + DSpark +
          # mmproj on CUDA (~10 GB) and placing the 12 non-looped 1x layers
          # (0..5, 18..23) + 4 loop layers (6..9) (~9.6 GB) in system RAM avoids
          # PCIe page thrashing while leavingUnified Memory as the OOM backstop.
          default =
            if cfg.gpuBackend == "cuda"
            then [ "^blk\\.([0-9]|1[89]|2[0-3])\\.ffn_(up|down|gate|gate_up)_(ch|)exps=CPU" ]
            else [ ];
          defaultText = literalExpression ''
            if config.services.llama-cpp.gpuBackend == "cuda"
            then [ "^blk\\.([0-9]|1[89]|2[0-3])\\.ffn_(up|down|gate|gate_up)_(ch|)exps=CPU" ]
            else [ ]
          '';
          description = "Tensor buffer placement overrides (-ot) for hybrid GPU + CPU RAM execution";
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
            # even inside single quotes, which would mangle `-ot` regex escapes.
            ExecStart = pkgs.writeShellScript "llama-cpp-start" ''
              exec ${escapeShellArgs serverArgs}
            '';
            Restart = "on-failure";
            RestartSec = 10;
            NoNewPrivileges = true;
            # GPU backends require /dev/nvidia* or /dev/dri — no DynamicUser.
          };
        };

        # Reachable over the NetBird mesh (and loopback).
        networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.port ];
      };
    };
}
