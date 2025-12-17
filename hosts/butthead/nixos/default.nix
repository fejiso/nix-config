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

  # Enable ROCm for ML/LLM/AI workloads
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };
  
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

  # MergerFS pool combining all data disks (SSD writes first)
  fileSystems."/mnt/user" = {
    device = "/mnt/data01:/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=ff"
    ];
  };

  # Slow storage pool (HDDs only, for aging files from SSD)
  fileSystems."/mnt/storage" = {
    device = "/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=epmfs"
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

  # Daily SnapRAID sync at 4am
  systemd.timers.snapraid-sync = {
    description = "Daily SnapRAID sync at 4am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "04:00";
      Persistent = true;
      Unit = "snapraid-sync.service";
    };
  };

  # SSD cache migration script
  systemd.services.ssd-migrate = {
    description = "Migrate old files from SSD to HDD pool";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ssd-migrate" ''
        set -e

        # Find files on SSD older than 24h, not currently open, and move to HDD pool
        ${pkgs.findutils}/bin/find /mnt/data01 -type f -mtime +1 -size +1M \
          ! -name "*.partial" ! -name "*.tmp" ! -path "*/.snapraid.content" \
          -print0 | while IFS= read -r -d "" file; do

          # First check if file is open
          if ! ${pkgs.lsof}/bin/lsof "$file" >/dev/null 2>&1; then
            # Get relative path
            relpath="''${file#/mnt/data01/}"
            targetdir="/mnt/storage/$(dirname "$relpath")"

            # Create target directory if needed
            mkdir -p "$targetdir"

            # Double-check file is not open right before transfer
            if ! ${pkgs.lsof}/bin/lsof "$file" >/dev/null 2>&1; then
              # Move file (rsync for safety, then remove source)
              if ${pkgs.rsync}/bin/rsync -a --remove-source-files "$file" "$targetdir/"; then
                echo "Migrated: $relpath"
              else
                echo "Failed to migrate: $relpath" >&2
              fi
            else
              echo "Skipped (opened during check): $relpath"
            fi
          fi
        done

        # Remove empty directories on SSD
        ${pkgs.findutils}/bin/find /mnt/data01 -type d -empty -delete 2>/dev/null || true
      '';
    };
  };

  systemd.timers.ssd-migrate = {
    description = "Daily SSD to HDD migration at 3am";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "03:00";
      Persistent = true;
    };
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

    # ROCm for ML/AI
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
  ];

  # System state version (override common config)
  system.stateVersion = lib.mkForce "25.11";
}