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
      };

      config = lib.mkIf cfg.enable (lib.mkMerge [
        # --- Common client + Icecream local daemon (mounted into Nix sandboxes via /run/icecc?) ---
        {
          users.users.icecc = {
            isSystemUser = true;
            group = "icecc";
            description = "Icecream unprivileged compile worker user";
          };
          users.groups.icecc = { };

          environment.systemPackages = [
            pkgs.icecream
            sccachePkg
          ];

          environment.etc."sccache/config".source = sccacheClientConf;
          environment.variables.SCCACHE_CONF = "/etc/sccache/config";

          # iceccd starts as root so it can retain its privileged chroot helper for
          # remote Nix compiler tarballs, then immediately drops to `-u icecc`.
          systemd.services.icecc-daemon = {
            description = "Icecream distributed C/C++ daemon (NetBird ${cfg.interface})";
            after = [ "network-online.target" "netbird.service" ]
              ++ lib.optional cfg.scheduler "icecc-scheduler.service";
            wants = [ "network-online.target" ];
            wantedBy = [ "multi-user.target" ];
            serviceConfig = {
              ExecStartPre = waitForWt0Script;
              ExecStart = lib.escapeShellArgs (
                [
                  "${pkgs.icecream}/bin/iceccd"
                  "-i" cfg.interface
                  "-p" (toString cfg.iceccDaemonPort)
                  "-s" "${cfg.schedulerAddr}:${toString cfg.iceccSchedulerPort}"
                  "-n" cfg.netName
                  "-m" (toString cfg.jobs)
                  "--nice" "5"
                  "-u" "icecc"
                  "-b" "/var/cache/icecc"
                  "--cache-limit" "2048"
                  "-N" hostname
                ]
                ++ lib.optional cfg.clientOnly "--no-remote"
              );
              RuntimeDirectory = "icecc";
              RuntimeDirectoryMode = "0755";
              CacheDirectory = "icecc";
              Slice = "builders.slice";
              OOMScoreAdjust = 500;
              Restart = "always";
              RestartSec = 5;
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
              # Cap sccache-dist worker CPU to logicalCores / 2 (Rust's
              # available_parallelism() reads cgroup v2 CPUQuota and reports
              # `cfg.jobs` slots directly to the sccache-dist scheduler).
              CPUQuota = "${toString (cfg.jobs * 100)}%";
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

          networking.firewall.interfaces.${cfg.interface}.allowedTCPPorts = [
            cfg.iceccSchedulerPort
            cfg.sccacheSchedulerPort
          ];
        })
      ]);
    };
}
