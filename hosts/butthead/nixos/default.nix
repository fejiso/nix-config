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
  # Individual data disk mounts
  fileSystems."/mnt/data01" = {
    device = "/dev/disk/by-label/data01"; # sdc1 - 953.9G
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/data02" = {
    device = "/dev/disk/by-label/data02"; # sda1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/data03" = {
    device = "/dev/disk/by-label/data03"; # sdb1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/data04" = {
    device = "/dev/disk/by-label/data04"; # sde1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/data05" = {
    device = "/dev/disk/by-label/data05"; # sdf1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  fileSystems."/mnt/data06" = {
    device = "/dev/disk/by-label/data06"; # sdh1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  # Parity disk mounts
  fileSystems."/mnt/parity1" = {
    device = "/dev/disk/by-label/parity1"; # sdg1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

  # Parity2 - sdd1 not formatted yet
  # fileSystems."/mnt/parity2" = {
  #   device = "/dev/disk/by-label/parity2"; # sdd1 - 7.3T
  #   fsType = "btrfs";
  #   options = [ "defaults" "noatime" ];
  # };

  # MergerFS pool combining all data disks
  fileSystems."/mnt/user" = {
    device = "/mnt/data01:/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=mfs"
    ];
  };

  # SnapRAID configuration
  services.snapraid = {
    enable = true;
    dataDisks = {
      d1 = "/mnt/data01";
      d2 = "/mnt/data02";
      d3 = "/mnt/data03";
      d4 = "/mnt/data04";
      d5 = "/mnt/data05";
      d6 = "/mnt/data06";
    };
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
      # "/mnt/parity2/snapraid.2-parity"  # Add when sdd1 is formatted
    ];
    contentFiles = [
      "/var/snapraid/snapraid.content"
      "/mnt/data01/.snapraid.content"
      "/mnt/data02/.snapraid.content"
      "/mnt/data03/.snapraid.content"
      "/mnt/data04/.snapraid.content"
      "/mnt/data05/.snapraid.content"
      "/mnt/data06/.snapraid.content"
    ];
  };

  # Enable media and download services in containers
  services.media-stack = {
    enable = true;
    dataDir = "/mnt/user";
    services = {
      sonarr.enable = true;
      radarr.enable = true;
      lidarr.enable = true;
      prowlarr.enable = true;
      emby.enable = true;
    };
  };

  services.download-stack = {
    enable = true;
    downloadDir = "/mnt/user/downloads";
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

  # System state version (override common config)
  system.stateVersion = lib.mkForce "25.11";
}