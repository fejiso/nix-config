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
    ./nats.nix
    ./metrics.nix
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

  # Static IPv6 — Hetzner doesn't do SLAAC/DHCPv6
  networking.interfaces.enp41s0 = {
    useDHCP = true; # Keep IPv4 DHCP working (interface exits NetworkManager)
    ipv6.addresses = [{
      address = "2a01:4f9:6b:2ba4::1";
      prefixLength = 64;
    }];
  };
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp41s0";
  };

  # Enable development tools and aarch64 emulation
  development.enable = true;

  # Override SSH settings for server access
  services.openssh.settings = {
    PermitRootLogin = lib.mkForce "yes";
    PasswordAuthentication = lib.mkForce true;
    KbdInteractiveAuthentication = lib.mkForce true;
  };
  
  # Tdarr worker node (native NixOS service)
  services.tdarr-worker = {
    enable = true;
  };

  # OpenClaw AI assistant (Kimi K3 via Moonshot provider; key from
  # secrets/kimi.yml, injected as KIMI_API_KEY/MOONSHOT_API_KEY by the module)
  services.openclaw = {
    enable = true;
    port = 3080;
    dataDir = "/var/lib/openclaw";
    model = "moonshot/kimi-k3";
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

  # llama.cpp distributed inference master (module: system-modules/llama-rpc.nix)
  # llama-server orchestrates RPC workers (desktops that come and go — the
  # membership probe restarts the master when the reachable set changes).
  # API only on the netbird mesh: http://hierro.netbird.cloud:8079
  services.llama-rpc.master = {
    enable = true;
    workers = [ "butthead" "elitedex" "blacktop" ];
    # Public GGUF; change to whatever model you want (downloaded once to
    # /var/lib/llama-models by llama-rpc-model-fetch).
    modelUrl = "https://huggingface.co/bartowski/Qwen2.5-7B-Instruct-GGUF/resolve/main/Qwen2.5-7B-Instruct-Q4_K_M.gguf";
  };

  # System state version
  system.stateVersion = "25.05";
}
