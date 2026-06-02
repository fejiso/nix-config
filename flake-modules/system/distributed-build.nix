{ inputs, ... }: {
  flake.modules.nixos.default =
{ config, lib, pkgs, hostname, ... }:

with lib;

let
  buildKeys = import "${inputs.self}/lib/build-keys.nix" { inherit lib; };
  keys = buildKeys.keys;

  # Define all build machines with their capabilities
  buildHosts = {
    butthead = {
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 4;  # Desktop with good CPU
      supportedFeatures = [ "kvm" "big-parallel" ];
      alwaysOn = true;  # Always available for cache
    };
    hierro = {
      system = "x86_64-linux";
      maxJobs = 2;
      speedFactor = 3;  # Server with good CPU
      supportedFeatures = [ "kvm" "big-parallel" ];
      alwaysOn = true;  # Always available for cache
    };
    blacktop = {
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 1;  # Laptop
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Laptop, not always on
    };
    elitedex = {
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Not always on
    };
    lenovix = {
      system = "x86_64-linux";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = [ "kvm" ];
      alwaysOn = false;  # Not always on
    };
    # Native aarch64 builder (Ubuntu + Determinate Nix). Saves hierro from
    # qemu-emulating ARM builds. Uses the regular `ubuntu` login user since
    # there's no nix-daemon to constrain a `nix-ssh` role account on. Legacy
    # `ssh://` protocol because amp1's nix (2.31.5) and hierro's nix-daemon
    # (2.34.7) disagree on ssh-ng wire format mid-build.
    amp1 = {
      system = "aarch64-linux";
      maxJobs = 4;
      speedFactor = 1;
      supportedFeatures = [ ];
      alwaysOn = true;
      sshUser = "ubuntu";
      protocol = "ssh";
      # Ubuntu host with Determinate Nix — no NixOS-managed nix-serve, so
      # don't advertise it as a substituter (avoids `Failed to connect to
      # amp1.netbird.cloud port 5000` spam during every fetch).
      serveCache = false;
    };
  };

  # Build list of other hosts (exclude current host)
  otherHosts = lib.filterAttrs (name: _: name != hostname) buildHosts;

  # Hosts that serve a nix-serve binary cache. Defaults to `alwaysOn`,
  # overridable per-host (e.g. amp1, which runs Determinate Nix on Ubuntu).
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
    stalled-download-timeout = 5;
    http-connections = 25;
    fallback = true;
    narinfo-cache-negative-ttl = 10;
    warn-dirty = false;
    # Limit local builds to encourage distribution
    max-jobs = lib.mkDefault (if buildHosts?${hostname} then buildHosts.${hostname}.maxJobs else 2);
    # Cores per build job (slot). hierro builds locally (distributedBuilds
    # off), so give it 24; every other host caps each slot at 4.
    cores = if hostname == "hierro" then 24 else 4;
    # Allow z-247 user to be a trusted user for remote builds
    trusted-users = [ "z-247" ];
    extra-substituters = substituters;
    trusted-substituters = substituters;
    trusted-public-keys = trustedPublicKeys;
  };

  # Configure remote builders
  nix.buildMachines = buildMachines;

  # Distribute builds to remote machines. hierro is excluded: it builds
  # everything locally, which also stops its daemon from re-delegating
  # inbound build requests (the mutual-builder deadlock).
  nix.distributedBuilds = hostname != "hierro";

  # Accept inbound remote-build connections on the shared nix-ssh role account.
  # Creates user `nix-ssh` whose shell is locked to `nix-store --serve --write`.
  nix.sshServe = {
    enable = true;
    protocol = "ssh-ng";
    write = true;
    keys = [ buildKeys.nixBuilderPublicKey ];
  };

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
