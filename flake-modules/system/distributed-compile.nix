{ ... }: {
  flake.modules.nixos.cli = { config, lib, pkgs, hostname, ... }:
    let
      cfg = config.services.distributed-compile;

      # Logical thread counts across the fleet; worker slots default to logical / 2.
      logicalCoresByHost = {
        butthead = 32; # -> 16 slots
        tungsten = 28; # -> 14 slots
        hierro   = 24; # -> 12 slots
        blacktop = 8;  # -> 4 slots
        elitedex = 8;  # -> 4 slots
        lenovix  = 4;  # -> 2 slots
        hispanas = 4;  # -> 2 slots (clientOnly by default)
        a8       = 4;  # -> 2 slots (clientOnly by default)
        snuffles = 2;  # -> 1 slot  (clientOnly by default)
      };

      workerPoolHosts = [ "butthead" "tungsten" "hierro" "blacktop" "elitedex" "lenovix" ];
      clientOnlyHosts = [ "hispanas" "a8" "snuffles" ];

      defaultHalfCores =
        let n = logicalCoresByHost.${hostname} or 4;
        in lib.max 1 (builtins.div n 2);

      probeOnlineCoresScript = pkgs.writeShellScript "distributed-compile-probe" ''
        set -euo pipefail

        # Update fleet ccache L2 reachability flag for sandboxed ccache wrappers.
        mkdir -p /run/ccache
        if ${pkgs.netcat-openbsd}/bin/nc -z -w1 ${lib.escapeShellArg cfg.schedulerAddr} ${toString cfg.ccachePort} >/dev/null 2>&1; then
          : > /run/ccache/online
          chmod 0644 /run/ccache/online
        else
          rm -f /run/ccache/online
        fi

        mkdir -p /run/icecc

        mem_gib=$(${pkgs.gawk}/bin/awk '/^MemTotal:/ { printf "%d", ($2 + 1048575) / 1048576 }' /proc/meminfo)
        local_jobs=${toString cfg.jobs}
        if [ -r /run/icecc/local-slots ]; then
          read -r _ls < /run/icecc/local-slots || true
          if [[ "''${_ls:-}" =~ ^[0-9]+$ ]] && [ "$_ls" -gt 0 ]; then
            local_jobs="$_ls"
          fi
        fi
        total="$local_jobs"

        # Query icecc-scheduler's text control port (schedulerPort + 1, default 8766)
        # via `listcs` for the live sum of `maxJobs` across all connected remote workers.
        listcs_out=$(printf 'listcs\nquit\n' | ${pkgs.netcat-openbsd}/bin/nc -w1 ${lib.escapeShellArg cfg.schedulerAddr} ${toString (cfg.iceccSchedulerPort + 1)} 2>/dev/null || true)
        if [ -n "$listcs_out" ]; then
          online_sum=$(printf '%s\n' "$listcs_out" | ${pkgs.gawk}/bin/awk '
            /\([0-9.]+:[1-9][0-9]*\)/ && match($0, /jobs=[0-9]+\/[0-9]+/) {
              s = substr($0, RSTART, RLENGTH)
              sub(/^jobs=[0-9]+\//, "", s)
              sum += s + 0
            }
            END { print sum + 0 }
          ')
          if [ "$online_sum" -gt 0 ]; then
            clamped="$online_sum"
            # Local g++ -E preprocessing still runs on the submitting host (~0.5-1 GiB
            # peak per heavy C++ TU), so never fan out wider than 1 job per GiB of RAM.
            if [ "$clamped" -gt "$mem_gib" ]; then
              clamped="$mem_gib"
            fi
            if [ "$clamped" -lt "$local_jobs" ]; then
              clamped="$local_jobs"
            fi
            total="$clamped"
          fi
        fi

        mkdir -p /run/icecc
        printf '%s\n' "$total" > /run/icecc/.online-cores.tmp
        chmod 0644 /run/icecc/.online-cores.tmp
        mv -f /run/icecc/.online-cores.tmp /run/icecc/online-cores
      '';

      isNativeX86_64 =
        pkgs.stdenv.buildPlatform == pkgs.stdenv.hostPlatform
        && pkgs.stdenv.hostPlatform.isx86_64;

      waitForWt0Script = pkgs.writeShellScript "wait-for-wt0-ipv4" ''
        set -euo pipefail
        for _ in $(seq 1 60); do
          ip4=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${lib.escapeShellArg cfg.interface} 2>/dev/null \
            | ${pkgs.gawk}/bin/awk '{split($4, a, "/"); print a[1]; exit}')
          if [ -n "''${ip4:-}" ]; then
            exit 0
          fi
          sleep 1
        done
        echo "${cfg.interface} did not acquire an IPv4 address within 60s" >&2
        exit 1
      '';

      sccachePkg = pkgs.sccache-dist;

      sccacheClientConf = pkgs.writeText "sccache-client.toml" ''
        [dist]
        scheduler_url = "http://${cfg.schedulerAddr}:${toString cfg.sccacheSchedulerPort}"
        toolchains = []
        toolchain_cache_size = 5368709120

        [dist.auth]
        type = "token"
        token = "dangerously_insecure_client"
      '';
    in
    {
      options.services.distributed-compile = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = isNativeX86_64 && (builtins.elem hostname (workerPoolHosts ++ clientOnlyHosts));
          defaultText = lib.literalExpression "isNativeX86_64 && elem hostname (workerPoolHosts ++ clientOnlyHosts)";
          description = "Enable NetBird-bound Icecream + sccache-dist distributed compilation.";
        };

        scheduler = lib.mkOption {
          type = lib.types.bool;
          default = hostname == "hierro";
          defaultText = lib.literalExpression ''hostname == "hierro"'';
          description = "Run the central Icecream & sccache-dist schedulers on this host (wt0 only).";
        };

        clientOnly = lib.mkOption {
          type = lib.types.bool;
          default = builtins.elem hostname clientOnlyHosts;
          defaultText = lib.literalExpression "elem hostname clientOnlyHosts";
          description = "Offload compiles to the cluster without accepting remote jobs onto this host.";
        };

        interface = lib.mkOption {
          type = lib.types.str;
          default = "wt0";
          description = "NetBird WireGuard interface to bind all distributed compile daemons and firewall rules to.";
        };

        schedulerAddr = lib.mkOption {
          type = lib.types.str;
          default = "100.107.225.121"; # hierro.netbird.cloud
          description = "NetBird IPv4 address of the central scheduler host (hierro).";
        };

        netName = lib.mkOption {
          type = lib.types.str;
          default = "NIXFLEET";
          description = "Icecream cluster network name.";
        };

        jobs = lib.mkOption {
          type = lib.types.ints.positive;
          default = defaultHalfCores;
          defaultText = lib.literalExpression "logicalCores / 2";
          description = "Worker compile slots advertised by this host (defaults to logical cores / 2).";
        };

        iceccSchedulerPort = lib.mkOption {
          type = lib.types.port;
          default = 8765;
        };

        iceccDaemonPort = lib.mkOption {
          type = lib.types.port;
          default = 10245;
        };

        sccacheSchedulerPort = lib.mkOption {
          type = lib.types.port;
          default = 10600;
        };

        sccacheServerPort = lib.mkOption {
          type = lib.types.port;
          default = 10501;
        };

        ccachePort = lib.mkOption {
          type = lib.types.port;
          default = 6380;
          description = "NetBird TCP port for the central Valkey ccache L2 server on hierro.";
        };

        ccacheL2MaxMemory = lib.mkOption {
          type = lib.types.str;
          default = "4gb";
          description = "LRU memory cap for hierro's central Valkey ccache L2 (~12-15 GB raw .o capacity with zstd).";
        };
      };

      config = lib.mkIf cfg.enable (lib.mkMerge [
        # --- Common client + Icecream local daemon + two-tier ccache ---
        {
          users.users.icecc = {
            isSystemUser = true;
            group = "icecc";
            description = "Icecream unprivileged compile worker user";
          };
          users.groups.icecc = { };

          environment.systemPackages = [
            pkgs.ccache
            pkgs.icecream
            sccachePkg
          ];

          # Local L1 ccache directory shared across nixbld* sandbox users (setgid + 002 umask)
          # and /run/ccache runtime dir for the socket-activated wt0 L2 bridge.
          systemd.tmpfiles.rules = [
            "d /var/cache/ccache 2775 root nixbld -"
            "d /run/ccache 0755 root root -"
            "d /run/icecc 0755 icecc icecc -"
            "d /var/cache/icecc 0775 icecc icecc -"
          ];

          # Socket-activated Unix-to-wt0 bridge so strict Nix sandboxes (CLONE_NEWNET)
          # can read/write the shared Valkey ccache L2 on hierro via /run/ccache/l2.sock.
          systemd.sockets.ccache-l2-proxy = {
            description = "Unix socket bridge to NetBird ccache L2 cache";
            wantedBy = [ "sockets.target" ];
            listenStreams = [ "/run/ccache/l2.sock" ];
            socketConfig = {
              DirectoryMode = "0755";
              SocketMode = "0666";
            };
          };

          systemd.services.ccache-l2-proxy = {
            description = "Proxy /run/ccache/l2.sock to NetBird ccache L2 (${cfg.schedulerAddr}:${toString cfg.ccachePort})";
            requires = [ "ccache-l2-proxy.socket" ];
            after = [ "ccache-l2-proxy.socket" ];
            serviceConfig = {
              ExecStart = "${pkgs.systemd}/lib/systemd/systemd-socket-proxyd --exit-idle-time=5min ${cfg.schedulerAddr}:${toString cfg.ccachePort}";
              DynamicUser = true;
            };
          };

          environment.etc."sccache/config".source = sccacheClientConf;
          environment.variables.SCCACHE_CONF = "/etc/sccache/config";

          # iceccd starts as root so it can retain its privileged chroot helper for
          # remote Nix compiler tarballs, then immediately drops to `-u icecc`.
          # Worker slots are clamped by min(logicalCores / 2, MemTotal_GiB / 3) so
          # simultaneous nixbld + iceccd + sccache-dist jobs always fit in builders.slice.
          systemd.services.icecc-daemon = {
            description = "Icecream distributed C/C++ daemon (NetBird ${cfg.interface})";
            after = [ "network-online.target" "netbird.service" ]
              ++ lib.optional cfg.scheduler "icecc-scheduler.service";
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            environment.ICECC_TEST_SOCKET = "/run/icecc/iceccd.socket";
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = pkgs.writeShellScript "start-icecc-daemon" ''
                set -euo pipefail
                mem_gib=$(${pkgs.gawk}/bin/awk '/^MemTotal:/ { printf "%d", ($2 + 1048575) / 1048576 }' /proc/meminfo)
                ram_slots=$(( mem_gib / 3 ))
                if [ "$ram_slots" -lt 1 ]; then
                  ram_slots=1
                fi
                slots=${toString cfg.jobs}
                if [ "$ram_slots" -lt "$slots" ]; then
                  slots="$ram_slots"
                fi
                # iceccd drops UID/GID to `icecc` via capng_change_id (keeping only
                # CAP_SYS_CHROOT) BEFORE calling cleanup_cache(/var/cache/icecc) and
                # binding /run/icecc/iceccd.socket, so both dirs must be owned by icecc.
                mkdir -p /var/cache/icecc /run/icecc
                chown -R icecc:icecc /var/cache/icecc
                chmod 0775 /var/cache/icecc
                chown icecc:icecc /run/icecc
                chmod 0755 /run/icecc
                printf '%s\n' "$slots" > /run/icecc/local-slots
                chmod 0644 /run/icecc/local-slots
                exec ${lib.escapeShellArgs (
                  [
                    "${pkgs.icecream}/bin/iceccd"
                    "-i" cfg.interface
                    "-p" (toString cfg.iceccDaemonPort)
                    "-n" cfg.netName
                    "-s" "${cfg.schedulerAddr}:${toString cfg.iceccSchedulerPort}"
                    "--nice" "5"
                    "-u" "icecc"
                    "-b" "/var/cache/icecc"
                    "--cache-limit" "2048"
                    "-N" hostname
                  ]
                  ++ lib.optional cfg.clientOnly "--no-remote"
                )} -m "$slots"
              '';
              RuntimeDirectory = "icecc";
              RuntimeDirectoryMode = "0755";
              RuntimeDirectoryPreserve = "yes";
              Slice = "builders.slice";
              OOMScoreAdjust = 500;
              Restart = "always";
              RestartSec = 5;
            };
          };

          # Periodically probe currently online wt0 Icecream workers + ccache L2 and
          # publish the aggregate slot count (clamped by local RAM) to /run/icecc/online-cores.
          systemd.services.distributed-compile-probe = {
            description = "Probe online NetBird Icecream workers & ccache L2";
            after = [ "icecc-daemon.service" "ccache-l2-proxy.socket" ];
            wantedBy = [ "multi-user.target" "icecc-daemon.service" ];
            serviceConfig = {
              Type = "oneshot";
              ExecStart = probeOnlineCoresScript;
            };
          };

          systemd.timers.distributed-compile-probe = {
            description = "Refresh online NetBird Icecream slot count every minute";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnBootSec = "15s";
              OnUnitActiveSec = "60s";
              AccuracySec = "10s";
            };
          };
        }

        # --- Worker pool: accept inbound Icecream & sccache-dist jobs on wt0 ---
        (lib.mkIf (!cfg.clientOnly) {
          systemd.services.sccache-dist-server = {
            description = "sccache-dist build worker (NetBird ${cfg.interface}, ${toString cfg.jobs} slots)";
            after = [ "network-online.target" "netbird.service" ]
              ++ lib.optional cfg.scheduler "sccache-dist-scheduler.service";
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            environment = {
              SCCACHE_NO_DAEMON = "1";
              SCCACHE_LOG = "info";
            };
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = pkgs.writeShellScript "start-sccache-dist-server" ''
                set -euo pipefail
                mem_gib=$(${pkgs.gawk}/bin/awk '/^MemTotal:/ { printf "%d", ($2 + 1048575) / 1048576 }' /proc/meminfo)
                ram_slots=$(( mem_gib / 3 ))
                if [ "$ram_slots" -lt 1 ]; then
                  ram_slots=1
                fi
                slots=${toString cfg.jobs}
                if [ "$ram_slots" -lt "$slots" ]; then
                  slots="$ram_slots"
                fi
                cg="/sys/fs/cgroup$(${pkgs.gawk}/bin/awk -F: '$1=="0"{print $3}' /proc/self/cgroup)"
                if [ -w "$cg/cpu.max" ]; then
                  printf '%s 100000\n' "$(( slots * 100000 ))" > "$cg/cpu.max" || true
                fi
                wt0_ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${lib.escapeShellArg cfg.interface} \
                  | ${pkgs.gawk}/bin/awk '{split($4, a, "/"); print a[1]; exit}')
                mkdir -p /var/cache/sccache-dist/toolchains /var/cache/sccache-dist/build
                cat > /run/sccache-dist-server/server.conf <<EOF
                cache_dir = "/var/cache/sccache-dist/toolchains"
                toolchain_cache_size = 10737418240
                public_addr = "''${wt0_ip}:${toString cfg.sccacheServerPort}"
                bind_address = "''${wt0_ip}:${toString cfg.sccacheServerPort}"
                scheduler_url = "http://${cfg.schedulerAddr}:${toString cfg.sccacheSchedulerPort}"

                [builder]
                type = "overlay"
                build_dir = "/var/cache/sccache-dist/build"
                bwrap_path = "${pkgs.bubblewrap}/bin/bwrap"

                [scheduler_auth]
                type = "DANGEROUSLY_INSECURE"
                EOF
                exec ${sccachePkg}/bin/sccache-dist server --config /run/sccache-dist-server/server.conf
              '';
              RuntimeDirectory = "sccache-dist-server";
              RuntimeDirectoryMode = "0700";
              CacheDirectory = "sccache-dist";
              # Cap sccache-dist worker CPU to min(logicalCores / 2, MemTotal_GiB / 3)
              # (Rust's available_parallelism() reads cgroup v2 cpu.max and reports
              # the clamped slot count directly to the sccache-dist scheduler).
              CPUQuota = "${toString (cfg.jobs * 100)}%";
              Delegate = [ "cpu" ];
              Nice = 5;
              Slice = "builders.slice";
              OOMScoreAdjust = 500;
              Restart = "always";
              RestartSec = 5;
            };
          };

          networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
            cfg.iceccDaemonPort
            cfg.sccacheServerPort
          ];
        })

        # --- Central schedulers on hierro (wt0 only) ---
        (lib.mkIf cfg.scheduler {
          systemd.services.icecc-scheduler = {
            description = "Icecream central scheduler (NetBird ${cfg.interface})";
            after = [ "network-online.target" "netbird.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = lib.escapeShellArgs [
                "${pkgs.icecream}/bin/icecc-scheduler"
                "-i" cfg.interface
                "-p" (toString cfg.iceccSchedulerPort)
                "-n" cfg.netName
                "-r"
              ];
              DynamicUser = true;
              Restart = "always";
              RestartSec = 5;
            };
          };

          systemd.services.sccache-dist-scheduler = {
            description = "sccache-dist central scheduler (NetBird ${cfg.interface})";
            after = [ "network-online.target" "netbird.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            environment = {
              SCCACHE_NO_DAEMON = "1";
              SCCACHE_LOG = "info";
            };
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = pkgs.writeShellScript "start-sccache-dist-scheduler" ''
                set -euo pipefail
                wt0_ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${lib.escapeShellArg cfg.interface} \
                  | ${pkgs.gawk}/bin/awk '{split($4, a, "/"); print a[1]; exit}')
                cat > /run/sccache-dist-scheduler/scheduler.conf <<EOF
                public_addr = "''${wt0_ip}:${toString cfg.sccacheSchedulerPort}"

                [client_auth]
                type = "DANGEROUSLY_INSECURE"

                [server_auth]
                type = "DANGEROUSLY_INSECURE"
                EOF
                exec ${sccachePkg}/bin/sccache-dist scheduler --config /run/sccache-dist-scheduler/scheduler.conf
              '';
              RuntimeDirectory = "sccache-dist-scheduler";
              RuntimeDirectoryMode = "0700";
              DynamicUser = true;
              Restart = "always";
              RestartSec = 5;
            };
          };

          systemd.services.ccache-l2-server = {
            description = "Central Valkey ccache L2 server (NetBird ${cfg.interface})";
            after = [ "network-online.target" "netbird.service" ];
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = pkgs.writeShellScript "start-ccache-l2-server" ''
                set -euo pipefail
                wt0_ip=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev ${lib.escapeShellArg cfg.interface} \
                  | ${pkgs.gawk}/bin/awk '{split($4, a, "/"); print a[1]; exit}')
                cat > /run/ccache-l2-server/valkey.conf <<EOF
                bind ''${wt0_ip}
                port ${toString cfg.ccachePort}
                protected-mode no
                tcp-keepalive 60
                maxmemory ${cfg.ccacheL2MaxMemory}
                maxmemory-policy allkeys-lru
                dir /var/lib/ccache-l2
                save 3600 100
                appendonly no
                EOF
                exec ${pkgs.valkey}/bin/valkey-server /run/ccache-l2-server/valkey.conf
              '';
              RuntimeDirectory = "ccache-l2-server";
              RuntimeDirectoryMode = "0700";
              StateDirectory = "ccache-l2";
              StateDirectoryMode = "0700";
              DynamicUser = true;
              Restart = "always";
              RestartSec = 5;
            };
          };

          networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
            cfg.iceccSchedulerPort
            (cfg.iceccSchedulerPort + 1) # text status port (`listcs`)
            cfg.sccacheSchedulerPort
            cfg.ccachePort
          ];
        })
      ]);
    };
}
