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
    ../../common/nixos/nix.nix
    ../../common/nixos/users.nix
    ../../common/nixos/security.nix
    ../../common/nixos/networking.nix
    ../../common/nixos/services.nix
    ../../common/nixos/sops.nix
    ../../common/nixos/distributed-build.nix
    ../../common/nixos/netbird.nix
    (import ../../../modules/nixos/desktop.nix)
    (import ../../../modules/nixos/systemd-nspawn.nix)
    (import ../../../modules/nixos/media-services.nix)
    (import ../../../modules/nixos/download-services.nix)
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  
  # Host-specific networking
  networking.hostName = "butthead";

  # Enable container support for media services
  boot.enableContainers = true;
  
  # Storage configuration for media server
  # Note: This will need to be customized based on actual hardware
  fileSystems."/mnt/storage" = {
    device = "none";
    fsType = "tmpfs"; # Placeholder - replace with actual mergerfs config
    options = [ "defaults" ];
  };

  # SnapRAID configuration (placeholder)
  # services.snapraid = {
  #   enable = true;
  #   # Will be configured based on actual disk layout
  # };

  # Enable media and download services in containers
  services.media-stack = {
    enable = true;
    dataDir = "/mnt/storage";
    services = {
      sonarr.enable = true;
      radarr.enable = true;
      lidarr.enable = true;
      prowlarr.enable = true;
      jellyfin.enable = true;
      emby.enable = true;
    };
  };
  
  services.download-stack = {
    enable = true;
    downloadDir = "/mnt/storage/downloads";
    services = {
      qbittorrent.enable = true;
      sabnzbd.enable = true;
      deluge.enable = true;
    };
  };

  # Additional packages for media server functionality
  environment.systemPackages = with pkgs; [
    # Storage and filesystem tools
    mergerfs
    snapraid
    
    # Container management tools are included in systemd
    # systemd includes machinectl for container management
    
    # Media tools
    ffmpeg
    mediainfo
    
    # Monitoring
    ncdu
    iotop
  ];

  # System state version
  system.stateVersion = "25.11";
}