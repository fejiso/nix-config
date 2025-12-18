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

  # Enable Podman for nginx-proxy-manager
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
  };

  # Enable ROCm for ML/LLM/AI workloads and create service directories
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    "d /var/lib/nginx-proxy-manager 0755 nginx-proxy-manager nginx-proxy-manager -"
    "d /var/lib/nginx-proxy-manager/data 0755 nginx-proxy-manager nginx-proxy-manager -"
    "d /var/lib/nginx-proxy-manager/letsencrypt 0755 nginx-proxy-manager nginx-proxy-manager -"
    "d /run/user/13200 0700 nginx-proxy-manager nginx-proxy-manager -"
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

  # Parity2
  fileSystems."/mnt/parity2" = {
    device = "/dev/disk/by-label/parity2"; # sdd1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" ];
  };

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
      "/mnt/parity2/snapraid.2-parity"  # Add when sdd1 is formatted
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
    hdparm

    # Container management tools
    shadow  # Required for rootless Podman (newuidmap/newgidmap)

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

  # Aggressive VFS caching to keep directory structure in RAM
  boot.kernel.sysctl = {
    "vm.vfs_cache_pressure" = 10; # Keep dentries/inodes in cache (default 100)
    "vm.dirty_writeback_centisecs" = 1500; # Delay writes to reduce spinups
  };

  # Aggressive drive spindown for HDDs
  systemd.services.hdd-spindown = {
    description = "Configure aggressive HDD spindown";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "hdd-spindown" ''
        # Apply aggressive spindown to all SATA drives except SSD (sdc)
        for disk in /dev/sd?; do
          disk_name=$(basename $disk)

          # Skip SSD cache disk
          if [ "$disk_name" = "sdc" ]; then
            ${pkgs.hdparm}/bin/hdparm -B 254 -S 0 $disk  # Never spin down SSD
            echo "SSD $disk: disabled spindown"
            continue
          fi

          # Aggressive spindown for HDDs: 5 minutes
          # -B 127 = minimum power management
          # -S 60 = spindown after 5 minutes
          ${pkgs.hdparm}/bin/hdparm -B 127 -S 60 $disk
          echo "HDD $disk: 5 minute spindown"
        done
      '';
    };
  };

  # NFS server configuration
  services.nfs.server = {
    enable = true;
    # Export /mnt/user to Netbird network (read-only) and blacktop (read-write)
    exports = ''
      /mnt/user 100.107.0.0/16(ro,sync,no_subtree_check,crossmnt,fsid=0) 100.107.6.184(rw,sync,no_subtree_check,crossmnt,fsid=0)
    '';
  };

  # Vaultwarden (Bitwarden-compatible server)
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN = "https://vaultwarden.example.com"; # Update with your actual domain
      ROCKET_ADDRESS = "0.0.0.0";
      ROCKET_PORT = 4743;
      SIGNUPS_ALLOWED = true;
      INVITATIONS_ALLOWED = true;
      WEBSOCKET_ENABLED = false;
    };
    environmentFile = "/var/lib/vaultwarden/vaultwarden.env";
  };

  # Open NFS ports in firewall
  networking.firewall = {
    allowedTCPPorts = [ 2049 111 20048 8102 8002 44302 3002 4743 ];
    allowedUDPPorts = [ 2049 111 20048 ];
  };

  # Dedicated user for nginx-proxy-manager
  users.users.nginx-proxy-manager = {
    isSystemUser = true;
    group = "nginx-proxy-manager";
    uid = 13200;
    home = "/var/lib/nginx-proxy-manager";
    createHome = true;
    subUidRanges = [{ startUid = 100000; count = 65536; }];
    subGidRanges = [{ startGid = 100000; count = 65536; }];
  };
  users.groups.nginx-proxy-manager = {
    gid = 13200;
  };

  # Nginx Proxy Manager container (rootless)
  systemd.services.nginx-proxy-manager = {
    description = "Nginx Proxy Manager";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "nginx-proxy-manager";
      Group = "nginx-proxy-manager";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "5min";

      # Environment for rootless Podman
      Environment = [
        "HOME=/var/lib/nginx-proxy-manager"
        "XDG_RUNTIME_DIR=/run/user/13200"
        "PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      ];

      ExecStartPre = [
        # Pull the latest image
        "${pkgs.podman}/bin/podman pull docker.io/jc21/nginx-proxy-manager:latest"
        # Remove old container if it exists
        "-${pkgs.podman}/bin/podman rm -f nginx-proxy-manager"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name nginx-proxy-manager \
          --memory=1G \
          -p 8102:81 \
          -p 8002:80 \
          -p 44302:443 \
          -p 3002:3000 \
          -v /var/lib/nginx-proxy-manager/data:/data:rw \
          -v /var/lib/nginx-proxy-manager/letsencrypt:/etc/letsencrypt:rw \
          -e DB_SQLITE_FILE=/data/database.sqlite \
          docker.io/jc21/nginx-proxy-manager:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 nginx-proxy-manager";
    };
  };

  # System state version (override common config)
  system.stateVersion = lib.mkForce "25.11";
}
