{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    ./forgejo.nix
    ./n8n.nix
    ./nats.nix
    ./metrics.nix
    ./polystack.nix
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  
  # Disable desktop/wayland services for server
  services.xserver.enable = lib.mkForce false;
  services.displayManager.sddm.enable = lib.mkForce false;
  services.pulseaudio.enable = lib.mkForce false;
  services.pipewire.enable = lib.mkForce false;
  
  # Network configuration
  networking.hostName = "hierro";

  # AMD Ryzen 9 3900 (Zen 2)
  hardware.cpu.tune = {
    cpu = "znver2";
    group = "x86-64-v3";
  };

  # Static IPv6 — Hetzner doesn't do SLAAC/DHCPv6; address lives in
  # secrets/network.yaml (sops) and is applied to enp41s0 after sops-nix runs.
  networking.interfaces.enp41s0.useDHCP = true; # Keep IPv4 DHCP working (interface exits NetworkManager)

  sops.secrets.hierro-ipv6 = {
    sopsFile = "${inputs.private}/secrets/network.yaml";
    key = "hierro/ipv6";
  };

  systemd.services.hierro-static-ipv6 = {
    description = "Configure Hetzner static IPv6 on enp41s0 from sops";
    after = [ "network-online.target" "sops-nix.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      addr=$(cat ${config.sops.secrets.hierro-ipv6.path})
      ${pkgs.iproute2}/bin/ip -6 addr replace "$addr" dev enp41s0
      ${pkgs.iproute2}/bin/ip -6 route replace default via fe80::1 dev enp41s0
    '';
  };

  # Enable development tools and aarch64 emulation
  development.enable = true;

  # Override SSH settings for server access
  services.openssh.settings = {
    PermitRootLogin = lib.mkForce "yes";
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
  };
  
  # Mount hispanas bcachefs pool at /mnt/hispanas over NetBird
  services.nfs-mounts.hispanas.enable = true;

  # Tdarr worker node (native NixOS service)
  services.tdarr-worker = {
    enable = true;
  };

  # OpenClaw AI assistant. Baseline = OpenCode Zen free models (key from
  # secrets/opencodego.yaml), OpenRouter deepseek-v4-flash as fallback; talk to
  # it via Telegram (bot token in secrets/openclaw.yaml).
  services.openclaw = {
    enable = true;
    port = 3080;
    dataDir = "/var/lib/openclaw";
    model = "opencode/big-pickle";
    modelFallbacks = [
      "opencode/nemotron-3-ultra-free"
      "openrouter/deepseek/deepseek-v4-flash"
    ];
    telegram.enable = true;
    # TODO: numeric Telegram user ID allowed to DM the bot (from @userinfobot)
    telegram.allowFrom = [ 000000000 ];
  };

  # Silverbullet runs as z-247's systemd USER service (see hosts/hierro/home);
  # keep the user manager alive on this headless host and open the port on the
  # netbird mesh only.
  systemd.services.enable-linger-z-247 = {
    description = "Enable lingering for z-247";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.systemd}/bin/loginctl enable-linger z-247";
    };
  };
  networking.firewall.interfaces.wt0.allowedTCPPorts = [ 3004 8888 ]; # silverbullet (user service), atuin

  # Atuin sync server for the personal fleet. Clients get the address from the
  # global default in flake-modules/home/shell.nix; only reachable on the
  # netbird mesh (firewall opens 8888 on wt0 only).
  services.atuin = {
    enable = true;
    host = "0.0.0.0";
    port = 8888;
    # Personal single-user server; needed so each host can register its account.
    openRegistration = true;
    # Default: local postgres (database.createLocally = true).
  };

  # Hourly flake builder — builds all host closures so nix-serve can distribute them
  systemd.services.nix-builder = {
    description = "Build all NixOS host configurations from flake";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ config.nix.package colmena gitMinimal openssh jq ];
    serviceConfig = {
      Type = "oneshot";
      StateDirectory = "nix-builder";
      ExecStart = "${pkgs.bash}/bin/bash ${../../../scripts/nix-builder.sh}";
      Nice = 19;
      IOSchedulingPriority = 7;
      CPUSchedulingPolicy = "batch";
    };
  };

  systemd.timers.nix-builder = {
    description = "Hourly NixOS flake build";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "hourly";
      Persistent = true;
      RandomizedDelaySec = "5min";
    };
  };

  # Local llama.cpp inference server — Inkling 2 Mini (Unsloth UD-Q4_K_XL + mmproj)
  # Pure CPU inference (Ryzen 9 3900, 12 physical Zen 2 cores, AVX2 repacked GEMM/GEMV)
  services.llama-cpp = {
    enable = true;
    threads = 12;
    threadsBatch = 24;
  };

  # MeshCore OwlShack + Pinto(hispanas, *) <-> Dublin(lenovix, #ioi) selective bridge.
  # Allowlisted companion pubkeys, bridgedChannels, and local channels live in nix-config-private/meshcore.nix.
  services.owlstack =
    let
      privateMeshcore =
        if builtins.pathExists "${inputs.private}/meshcore.nix"
        then import "${inputs.private}/meshcore.nix"
        else { };
    in
    {
      enable = true;
      allowedCompanions = (privateMeshcore.allowedCompanions or [ ]) ++ [
        {
          name = "🟩🦅greenbird";
          pubKey = "04";
        }
      ];
    } // lib.optionalAttrs (privateMeshcore ? bridgedChannels) {
      inherit (privateMeshcore) bridgedChannels;
    } // lib.optionalAttrs (privateMeshcore ? zeroHopChannels) {
      inherit (privateMeshcore) zeroHopChannels;
    } // lib.optionalAttrs (privateMeshcore ? extraChannels || privateMeshcore ? channels) {
      extraChannels = privateMeshcore.extraChannels or privateMeshcore.channels;
    } // lib.optionalAttrs (privateMeshcore ? allowlistFile) {
      inherit (privateMeshcore) allowlistFile;
    };

  # System state version
  system.stateVersion = "25.05";
}
