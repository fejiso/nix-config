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
  
  # Tdarr worker node
  services.tdarr-worker = {
    enable = true;
    transcodeCache = "/mnt/downloadtemp/tdarr-cache";
  };

  # OpenClaw AI assistant
  services.openclaw = {
    enable = true;
    port = 3080;
    dataDir = "/var/lib/openclaw";
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

  # System state version
  system.stateVersion = "25.05";
}
