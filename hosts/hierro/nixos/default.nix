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
    ../../common/nixos
    (import ../../../modules/nixos/development.nix)
    (import ../../../modules/nixos/tdarr-worker.nix)
    (import ../../../modules/nixos/openclaw.nix)
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
