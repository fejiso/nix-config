{ ... }: {
  flake.modules.nixos.llama-rpc =
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.llama-rpc;

  backendFlags = {
    none = { };
    cuda = { cudaSupport = true; };
    rocm = { rocmSupport = true; };
    vulkan = { vulkanSupport = true; };
  };

  workerPackage = pkgs.llama-cpp.override ({ rpcSupport = true; } // backendFlags.${cfg.worker.gpuBackend});

  # Probe all configured workers over netbird and write the reachable ones
  # (comma-separated) to $1. Shared by the master's ExecStartPre and the
  # membership-change probe timer.
  probeScript = pkgs.writeShellScript "llama-rpc-probe" ''
    OUT="$1"
    mkdir -p "$(dirname "$OUT")"
    REACHABLE=""
    for host in ${concatStringsSep " " (map (w: "${w}.netbird.cloud") cfg.master.workers)}; do
      if ${pkgs.netcat-openbsd}/bin/nc -z -w2 "$host" ${toString cfg.master.workerPort} >/dev/null 2>&1; then
        if [ -n "$REACHABLE" ]; then REACHABLE="$REACHABLE,"; fi
        REACHABLE="$REACHABLE$host:${toString cfg.master.workerPort}"
      else
        echo "worker $host unreachable, skipping"
      fi
    done
    echo "$REACHABLE" > "$OUT.new"
    mv "$OUT.new" "$OUT"
    echo "reachable workers: ''${REACHABLE:-<none>}"
  '';

  masterPackage = pkgs.llama-cpp.override { rpcSupport = true; };
in
{
  options.services.llama-rpc = {
    master = {
      enable = mkEnableOption "llama.cpp master (llama-server with RPC backends)";

      port = mkOption {
        type = types.port;
        default = 8079;
        description = "HTTP API port for llama-server (netbird mesh only)";
      };

      modelUrl = mkOption {
        type = types.str;
        example = "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf";
        description = "URL (e.g. Hugging Face resolve URL) of the GGUF model to download if not already present";
      };

      modelsDir = mkOption {
        type = types.path;
        default = "/var/lib/llama-models";
        description = "Directory where the model file is stored";
      };

      workers = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "butthead" "elitedex" ];
        description = "Netbird hostnames of RPC workers; only reachable ones are used at (re)start";
      };

      workerPort = mkOption {
        type = types.port;
        default = 50052;
        description = "Port the workers' llama-rpc-server listens on";
      };

      probeInterval = mkOption {
        type = types.str;
        default = "minutely";
        description = "Systemd calendar expression for worker membership re-probing; master restarts only when the reachable set changes";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        example = [ "-ngl" "99" "--ctx-size" "8192" ];
        description = "Extra arguments passed to llama-server";
      };
    };

    worker = {
      enable = mkEnableOption "llama.cpp RPC worker (llama-rpc-server)";

      port = mkOption {
        type = types.port;
        default = 50052;
        description = "Port for llama-rpc-server (netbird mesh only)";
      };

      gpuBackend = mkOption {
        type = types.enum [ "none" "cuda" "rocm" "vulkan" ];
        default = "none";
        description = "GPU backend for the llama-cpp build (cuda/rocm/vulkan compile from source)";
      };

      extraArgs = mkOption {
        type = types.listOf types.str;
        default = [ ];
        description = "Extra arguments passed to llama-rpc-server";
      };
    };
  };

  config = mkMerge [
    (mkIf cfg.worker.enable {
      systemd.services.llama-rpc-worker = {
        description = "llama.cpp RPC worker";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "netbird.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          ExecStart = escapeShellArgs (
            [ "${workerPackage}/bin/llama-rpc-server" "--host" "0.0.0.0" "--port" (toString cfg.worker.port) ]
            ++ cfg.worker.extraArgs
          );
          Restart = "always";
          RestartSec = 5;
          NoNewPrivileges = true;
          # GPU backends need /dev/dri or /dev/kfd + /dev/nvidia* — no DynamicUser
        };
      };

      # RPC protocol has no auth and a history of RCEs — netbird mesh only
      networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.worker.port ];
    })

    (mkIf cfg.master.enable {
      systemd.services.llama-rpc-model-fetch = {
        description = "Download GGUF model for llama.cpp master";
        wantedBy = [ "llama-rpc-master.service" ];
        before = [ "llama-rpc-master.service" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        unitConfig.ConditionPathExists = "!${cfg.master.modelsDir}/${baseNameOf cfg.master.modelUrl}";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "llama-rpc-model-fetch" ''
            mkdir -p ${cfg.master.modelsDir}
            ${pkgs.curl}/bin/curl -fL --retry 3 -o ${cfg.master.modelsDir}/${baseNameOf cfg.master.modelUrl}.tmp ${escapeShellArg cfg.master.modelUrl}
            mv ${cfg.master.modelsDir}/${baseNameOf cfg.master.modelUrl}.tmp ${cfg.master.modelsDir}/${baseNameOf cfg.master.modelUrl}
          '';
        };
      };

      systemd.services.llama-rpc-master = {
        description = "llama.cpp master (llama-server with RPC backends)";
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" "netbird.service" "llama-rpc-model-fetch.service" ];
        wants = [ "network-online.target" ];
        serviceConfig = {
          RuntimeDirectory = "llama-rpc";
          ExecStartPre = "${probeScript} /run/llama-rpc/rpc-servers";
          ExecStart = pkgs.writeShellScript "llama-rpc-master" ''
            RPC_SERVERS=$(cat /run/llama-rpc/rpc-servers)
            ARGS=""
            if [ -n "$RPC_SERVERS" ]; then
              ARGS="--rpc $RPC_SERVERS"
            fi
            echo "starting llama-server with RPC workers: ''${RPC_SERVERS:-<none, CPU only>}"
            exec ${masterPackage}/bin/llama-server \
              --model ${cfg.master.modelsDir}/${baseNameOf cfg.master.modelUrl} \
              --host 0.0.0.0 \
              --port ${toString cfg.master.port} \
              $ARGS ${escapeShellArgs cfg.master.extraArgs}
          '';
          Restart = "on-failure";
          RestartSec = 10;
          NoNewPrivileges = true;
        };
      };

      # Desktops come and go: re-probe membership and restart the master only
      # when the reachable set changed.
      systemd.services.llama-rpc-membership = {
        description = "Probe llama.cpp RPC worker membership";
        serviceConfig = {
          Type = "oneshot";
          ExecStart = pkgs.writeShellScript "llama-rpc-membership" ''
            CURRENT=/run/llama-rpc/rpc-servers
            OLD=""
            [ -f "$CURRENT" ] && OLD=$(cat "$CURRENT")
            ${probeScript} "$CURRENT.probed"
            NEW=$(cat "$CURRENT.probed")
            if [ "$NEW" != "$OLD" ]; then
              echo "worker membership changed: '$OLD' -> '$NEW', restarting master"
              mv "$CURRENT.probed" "$CURRENT"
              systemctl restart llama-rpc-master.service
            else
              rm -f "$CURRENT.probed"
            fi
          '';
        };
      };

      systemd.timers.llama-rpc-membership = {
        description = "llama.cpp RPC worker membership probe timer";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = cfg.master.probeInterval;
          Persistent = true;
        };
      };

      # API reachable only via the netbird mesh
      networking.firewall.interfaces.wt0.allowedTCPPorts = [ cfg.master.port ];
    })
  ];
}
;
}
