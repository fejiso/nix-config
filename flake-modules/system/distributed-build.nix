{ inputs, ... }: {
  flake.modules.nixos.cli =
{ config, lib, pkgs, hostname, ... }:

with lib;

let
  buildKeys = import "${inputs.self}/lib/build-keys.nix" { inherit lib; };
  keys = buildKeys.keys;

  # Logical thread counts across the fleet; Nix `cores` and distributed compile
  # worker slots (icecream / sccache-dist) both use logicalCores / 2.
  logicalCoresByHost = {
    butthead = 32; # Ryzen 9 5950X (16C/32T) -> 16
    tungsten = 28; # Core i7-13850HX (8P+12E, 28T) -> 14
    hierro   = 24; # Ryzen 9 3900 (12C/24T) -> 12
    blacktop = 8;  # Ryzen 7 4700U (8C/8T) -> 4
    elitedex = 8;  # Ryzen 5 2400G (4C/8T) -> 4
    lenovix  = 4;  # Core i5-6500T (4C/4T) -> 2
    hispanas = 4;  # Core i3-3220 (2C/4T) -> 2
    a8       = 4;  # AMD A8-7410 (4C/4T) -> 2
    snuffles = 2;  # Celeron N3060 (2C/2T) -> 1
    quicksilver = 2; # Core 2 Duo SU7300 (2C/2T) -> 1
  };

  halfLogicalCores =
    if logicalCoresByHost ? ${hostname}
    then builtins.div logicalCoresByHost.${hostname} 2
    else 2;

  # Define all build machines with their capabilities
  # maxJobs = 1 on every host so `maxJobs * cores` never multiplies compiler
  # memory footprints (each single package gets `logicalCores / 2` threads).
  buildHosts = {
    butthead = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 4;  # Ryzen 9 5950X (32T)
      supportedFeatures = [ "kvm" "big-parallel" ];
      alwaysOn = true;  # Always available for cache
      # butthead is currently offline; prevent peers from stalling queries to it
      serveCache = false;
    };
    hierro = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 3;  # Ryzen 9 3900 (24T)
      supportedFeatures = [ "kvm" "big-parallel" ];
      alwaysOn = true;
      # nix-serve currently accepts connections but stalls responses. Keep
      # hierro as a builder, but stop peers from querying it as a substituter.
      serveCache = false;
    };
    tungsten = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 3;  # Core i7-13850HX (28T)
      supportedFeatures = [ "kvm" "big-parallel" ];
      alwaysOn = false;  # Laptop, not always on
    };
    blacktop = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 1;  # Laptop
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Laptop, not always on
    };
    elitedex = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 1;
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Not always on
    };
    lenovix = {
      system = "x86_64-linux";
      maxJobs = 1;
      speedFactor = 1;
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Not always on
    };
  };

  # Build list of other hosts (exclude current host)
  otherHosts = lib.filterAttrs (name: _: name != hostname) buildHosts;

  # Hosts that serve a nix-serve binary cache. Defaults to `alwaysOn`,
  # overridable per-host.
  cacheHosts = lib.filterAttrs
    (name: host: name != hostname && host.alwaysOn && (host.serveCache or true))
    buildHosts;

  # Convert to nix.buildMachines format
  buildMachines = lib.mapAttrsToList (name: host: {
    hostName = "${name}.netbird.cloud";
    system = host.system;
    sshUser = host.sshUser or "nix-ssh";
    sshKey = config.sops.secrets.nix-builder-key.path;
    maxJobs = host.maxJobs;
    speedFactor = host.speedFactor;
    supportedFeatures = host.supportedFeatures;
    protocol = host.protocol or "ssh-ng";
  } // (lib.optionalAttrs ((keys.${name}.hostPublicKey or "") != "") {
    publicHostKey = if lib.hasPrefix "ssh-ed25519 " keys.${name}.hostPublicKey
      then lib.substring 12 (lib.stringLength keys.${name}.hostPublicKey) keys.${name}.hostPublicKey
      else keys.${name}.hostPublicKey;
  })) otherHosts;

  # Generate substituter URLs only for hosts that actually serve a cache.
  substituters = lib.mapAttrsToList (name: _: "http://${name}.netbird.cloud:5000") cacheHosts;

  # Generate trusted public keys for all hosts
  trustedPublicKeys = lib.flatten (lib.mapAttrsToList (name: _: 
    if (keys.${name}.nixPublicKey or "") != "" then [ keys.${name}.nixPublicKey ] else []
  ) buildHosts);

  # System-wide SSH known_hosts entry for each fleet member that has a
  # recorded hostPublicKey. Removes the chicken-and-egg where `nix-daemon`
  # can't TOFU host keys non-interactively.
  knownHostsConfig = lib.mapAttrs' (name: host:
    lib.nameValuePair "fleet-${name}" {
      hostNames = [ "${name}.netbird.cloud" ];
      publicKey = "ssh-ed25519 ${keys.${name}.hostPublicKey}";
    }
  ) (lib.filterAttrs (name: _: (keys.${name}.hostPublicKey or "") != "") buildHosts);

in
{
  programs.ssh.knownHosts = knownHostsConfig;

  # Nix configuration
  nix.settings = {
    builders-use-substitutes = true;
    connect-timeout = 1;
    # connect-timeout=1 already fails fast past *offline* peers; this only
    # applies to peers that connected (alive). Keep it generous so a jittery
    # netbird link to butthead doesn't abort a large CUDA NAR mid-transfer
    # (butthead is the sole source for unfree CUDA — no fallback).
    stalled-download-timeout = 30;
    # Keep concurrent fetches modest: over a thin netbird link, 25 parallel
    # streams each get a starved slice and stall out. Fewer = more bandwidth
    # per NAR, fewer stall-timeouts.
    http-connections = 10;
    fallback = true;
    narinfo-cache-negative-ttl = 10;
    warn-dirty = false;
    # Keep 1 derivation per host at a time (`1 * logicalCores/2` threads) so
    # multiple C++/Rust builds never multiply RAM usage and trigger OOM.
    max-jobs = lib.mkDefault 1;
    # Cores per build job (logicalCores / 2 on each host).
    cores = halfLogicalCores;
    # Expose optional Icecream & two-tier ccache sockets/dirs into strict Nix sandboxes (`?` = skip if absent).
    extra-sandbox-paths = [ "/run/icecc?" "/run/ccache?" "/var/cache/ccache?" ];
    # Allow z-247 user to be a trusted user for remote builds. `nix-ssh` (the
    # locked role account remote builders connect as) must also be trusted so
    # it can receive *unsigned* build-input pushes over `nix-store --serve`.
    # Without this, copying a locally-built, unsigned input to a remote builder
    # fails with "cannot add path … lacks a signature by a trusted key" (peer
    # substitution still works because nix-serve signs at serve-time, but the
    # ssh build-input path does not).
    trusted-users = [ "z-247" "nix-ssh" ];
    # Sign locally-built paths with this host's nix-serve key (already in every
    # peer's trusted-public-keys) so they're trusted wherever they're copied.
    secret-key-files = "/var/lib/nix-serve/cache-priv-key.pem";
    extra-substituters = substituters;
    trusted-substituters = substituters;
    trusted-public-keys = trustedPublicKeys;
  };

  # Shared CPU- and memory-bounded cgroup slice for all local & distributed build
  # daemons (nix-daemon, icecc-daemon, sccache-dist-server):
  #   - CPUQuota = (logicalCores / 2) * 100%: caps combined CPU across all three
  #     daemons so the other half of the machine's threads stays completely free.
  #   - MemoryHigh = 65%: kernel throttles compiler allocations & reclaims into
  #     zswap/swap gracefully instead of OOM-killing cc1plus/rustc.
  #   - MemoryMax  = 80%: hard ceiling so runaway builds never starve user.slice,
  #     desktop sessions, SSH, or host services.
  systemd.slices.builders = {
    description = "CPU- and memory-bounded slice for Nix and distributed compiler daemons";
    sliceConfig = {
      CPUQuota = "${toString (halfLogicalCores * 100)}%";
      CPUWeight = 20;
      MemoryHigh = "65%";
      MemoryMax = "80%";
    };
  };

  systemd.services.nix-daemon.serviceConfig = {
    Slice = "builders.slice";
    OOMScoreAdjust = 500;
  };

  # Configure remote builders: NixOS renders the static roster to /etc/nix/machines,
  # while nix-builders-probe filters it every 60s into /run/nix-builders/machines
  # containing only peers currently reachable on TCP :22 over NetBird.
  nix.buildMachines = buildMachines;
  nix.settings.builders = lib.mkForce "@/run/nix-builders/machines";

  systemd.tmpfiles.rules = [
    "d /run/nix-builders 0755 root root -"
    "f /run/nix-builders/machines 0644 root root -"
  ];

  systemd.services.nix-builders-probe = {
    description = "Filter /etc/nix/machines to currently online SSH builders";
    after = [ "network-online.target" "netbird.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "nix-builders-probe" ''
        set -euo pipefail
        mkdir -p /run/nix-builders
        tmp=/run/nix-builders/.machines.tmp
        : > "$tmp"
        if [ -r /etc/nix/machines ]; then
          while IFS= read -r line || [ -n "$line" ]; do
            case "$line" in
              ""|\#*) continue ;;
            esac
            uri=''${line%%[[:space:]]*}
            host=''${uri#*://}
            host=''${host#*@}
            host=''${host%%:*}
            if [ -n "$host" ] && ${pkgs.netcat-openbsd}/bin/nc -z -w1 "$host" 22 >/dev/null 2>&1; then
              printf '%s\n' "$line" >> "$tmp"
            fi
          done < /etc/nix/machines
        fi
        chmod 0644 "$tmp"
        mv -f "$tmp" /run/nix-builders/machines
      '';
    };
  };

  systemd.timers.nix-builders-probe = {
    description = "Refresh online Nix remote builders every minute";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "15s";
      OnUnitActiveSec = "60s";
      AccuracySec = "10s";
    };
  };

  # Every host distributes its OWN builds to any peer. The mutual-builder
  # deadlock is prevented on the *inbound* side instead (see nix-ssh below):
  # a build that arrives over ssh is pinned to build locally and never
  # re-delegated, so cycles like butthead → lenovix → butthead can't form.
  nix.distributedBuilds = true;

  # Accept inbound remote-build connections on the shared nix-ssh role account.
  # Rolled by hand instead of `nix.sshServe` so the forced command can pin
  # `builders=""`: a build that ARRIVES here over ssh-ng is built locally and
  # never re-delegated to another remote. This is the half that breaks the
  # mutual-builder deadlock while still letting every host distribute its own
  # builds (distributedBuilds = true above). The per-connection `nix-daemon
  # --stdio` is a distinct process from this host's system daemon, so pinning
  # its builders empty does not affect the host's own outbound distribution.
  users.users.nix-ssh = {
    description = "Nix SSH store user";
    isSystemUser = true;
    group = "nix-ssh";
    shell = pkgs.bashInteractive;
    openssh.authorizedKeys.keys = [ buildKeys.nixBuilderPublicKey ];
  };
  users.groups.nix-ssh = { };

  services.openssh.enable = true;
  services.openssh.extraConfig = ''
    Match User nix-ssh
      AllowAgentForwarding no
      AllowTcpForwarding no
      PermitTTY no
      PermitTunnel no
      X11Forwarding no
      ForceCommand ${config.nix.package.out}/bin/nix-daemon --stdio --option builders ""
    Match All
  '';

  # Configure binary cache serving
  services.nix-serve = {
    enable = true;
    port = 5000;
    secretKeyFile = "/var/lib/nix-serve/cache-priv-key.pem";
  };

  # Ensure nix-serve user/group exist for keygen service
  users.users.nix-serve = {
    isSystemUser = true;
    group = "nix-serve";
  };
  users.groups.nix-serve = {};

  # Generate signing key if it doesn't exist
  systemd.services.nix-serve-keygen = {
    description = "Generate nix-serve signing key";
    wantedBy = [ "multi-user.target" ];
    before = [ "nix-serve.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      if [ ! -f /var/lib/nix-serve/cache-priv-key.pem ]; then
        mkdir -p /var/lib/nix-serve
        ${pkgs.nix}/bin/nix-store --generate-binary-cache-key ${hostname}.netbird.cloud /var/lib/nix-serve/cache-priv-key.pem /var/lib/nix-serve/cache-pub-key.pem
        chown nix-serve:nix-serve /var/lib/nix-serve/cache-*.pem
        chmod 600 /var/lib/nix-serve/cache-priv-key.pem
        chmod 644 /var/lib/nix-serve/cache-pub-key.pem
        echo "Generated signing keys for ${hostname}"
        echo "Public key: $(cat /var/lib/nix-serve/cache-pub-key.pem)"
      fi
    '';
  };

  # Open firewall for nix-serve
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 5000 ];
}
;
}
