{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}:
let
  # Helper function to create media service configurations
  mkMediaService = { name, port, volumes, image ? "lscr.io/linuxserver/${name}:latest" }: {
    description = lib.strings.toUpper (lib.substring 0 1 name) + lib.substring 1 (lib.stringLength name) name;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.podman ];

    serviceConfig = {
      Type = "simple";
      User = "media-podman";
      Group = "media-services";
      UMask = "0002";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "5min";

      # Resource limits for desktop usage
      CPUQuota = "150%";  # Max 1.5 CPU cores per service
      MemoryMax = "2G";   # Max 2GB RAM per service
      IOWeight = 100;     # Lower I/O priority

      Environment = [
        "HOME=/var/lib/media-podman"
        "XDG_RUNTIME_DIR=/run/user/13106"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f ${name}"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name ${name} \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p ${toString port}:${toString port} \
          ${lib.concatMapStringsSep " " (v: "-v ${v}") volumes} \
          -e PUID=0 \
          -e PGID=0 \
          -e UMASK=002 \
          -e TZ=Europe/Dublin \
          ${image}
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 ${name}";
    };
  };
in
{
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos
    (import ../../../modules/nixos/desktop.nix)
    (import ../../../modules/nixos/systemd-nspawn.nix)
    (import ../../../modules/nixos/media-services.nix)
    (import ../../../modules/nixos/download-services.nix)
    (import ../../../modules/nixos/tdarr.nix)
  ];

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";

  # Swap configuration for hibernation (64GB RAM + 2GB margin)
  swapDevices = [
    {
      device = "/swapfile";
      size = 67584; # 66GB in MB
    }
  ];

  # Hibernation configuration
  boot.resumeDevice = "/dev/mapper/crypted";
  # TODO: After swapfile is created, run: sudo btrfs inspect-internal map-swapfile -r /swapfile
  # Then set: boot.kernelParams = [ "resume_offset=XXXXX" ];

  # Host-specific networking
  networking.hostName = "butthead";

  # Enable container support for media services
  boot.enableContainers = true;

  # Enable Podman for nginx-proxy-manager
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    extraPackages = [ pkgs.slirp4netns ];
  };

  # Use podman for oci-containers
  virtualisation.oci-containers.backend = "podman";

  # Enable libvirt for VM management
  virtualisation.libvirtd = {
    enable = true;
    qemu = {
      package = pkgs.qemu_kvm;
      runAsRoot = false;
      swtpm.enable = true;
    };
  };

  # Ensure setuid wrappers for rootless podman
  security.wrappers = {
    newuidmap = {
      source = "${pkgs.shadow}/bin/newuidmap";
      setuid = true;
      owner = "root";
      group = "root";
    };
    newgidmap = {
      source = "${pkgs.shadow}/bin/newgidmap";
      setuid = true;
      owner = "root";
      group = "root";
    };
  };

  # Daily container image updates using podman auto-update
  systemd.timers.podman-auto-update = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      RandomizedDelaySec = "2h";
      Persistent = true;
    };
  };

  systemd.services.podman-auto-update = {
    description = "Update container images and restart if needed";
    serviceConfig = {
      Type = "oneshot";
    };
    script = ''
      # Update containers for all users with XDG_RUNTIME_DIR
      for runtime_dir in /run/user/*; do
        if [ -d "$runtime_dir" ]; then
          uid=$(basename "$runtime_dir")
          username=$(id -un "$uid" 2>/dev/null) || continue
          echo "Checking containers for user $username (UID $uid)"
          sudo -u "$username" XDG_RUNTIME_DIR="$runtime_dir" ${pkgs.podman}/bin/podman auto-update || true
        fi
      done
    '';
  };

  # Configure containers.conf for pasta networking
  virtualisation.containers.containersConf.settings = {
    network = {
      default_rootless_network_cmd = "pasta";
      pasta_options = ["--map-gw"];
    };
  };

  # Enable ROCm for ML/LLM/AI workloads and create service directories
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    "d /var/lib/nginx-proxy-manager 0755 nginx-proxy-manager nginx-proxy-manager -"
    "d /var/lib/npm-storage 0755 100000 100000 -"
    "Z /var/lib/npm-storage/data 0755 100000 100000 -"
    "Z /var/lib/npm-storage/letsencrypt 0755 100000 100000 -"
    "d /run/user/13200 0700 nginx-proxy-manager nginx-proxy-manager -"
    "d /run/user/13105 0700 emby-podman emby-podman -"
    "d /run/user/13110 0700 prowlarr-podman prowlarr-podman -"
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

    # Scrub configuration
    scrub = {
      interval = "02:00";  # Daily scrub at 2am
      plan = 5;  # Scrub 5% of array
      olderThan = 10;  # Prioritize blocks older than 10 days
    };

    # Sync configuration
    sync.interval = "04:00";  # Daily sync at 4am
  };

  # Enable btrfs automatic scrubbing
  services.btrfs.autoScrub = {
    enable = true;
    interval = "monthly";
    fileSystems = [ "/mnt/data01" "/mnt/data02" "/mnt/data03" "/mnt/data04" "/mnt/data05" "/mnt/data06" "/mnt/parity1" "/mnt/parity2" ];
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
  # Disabled - using podman services defined below instead
  # services.media-stack = {
  #   enable = false;
  # };

  # Disabled - using podman services defined below instead
  # services.download-stack = {
  #   enable = false;
  # };

  # Tdarr transcoding server
  services.tdarr = {
    enable = true;
    server = {
      enable = true;
      internalNode = false;  # Use separate node for better control
    };
    node = {
      enable = true;
      nodeId = "butthead_worker";
    };
    mediaDirectories = {
      tv = "/mnt/user/Series";
      movies = "/mnt/user/Movies";
    };
    transcodeCache = "/mnt/user/downloadtemp/tdarr-cache";
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
    # Export individual directories to Netbird network
    exports = ''
      /mnt/user/Series 100.107.0.0/16(ro,sync,no_subtree_check,fsid=1)
      /mnt/user/Videos 100.107.0.0/16(ro,sync,no_subtree_check,fsid=2)
      /mnt/user/Music 100.107.0.0/16(ro,sync,no_subtree_check,fsid=3) 100.107.6.184(rw,sync,no_subtree_check,fsid=3)
      /mnt/user/ROMs 100.107.0.0/16(ro,sync,no_subtree_check,fsid=4)
      /mnt/user/Backups 100.107.0.0/16(rw,sync,no_subtree_check,fsid=5)
    '';
  };

  # Vaultwarden (Bitwarden-compatible server)
  services.vaultwarden = {
    enable = true;
    config = {
      DOMAIN = "https://vaultwarden.fer.xyz";
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
    allowedTCPPorts = [ 2049 111 20048 8102 8002 44302 3002 4743 8096 8080 8989 7878 8686 9696 5299 8081 8112 3344 8000 ];
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

  # Shared group for media services
  users.groups.media-services = {
    gid = 13100;
  };

  # Enable lingering for podman users to create /run/user/UID directories
  systemd.services.enable-linger-podman-users = {
    description = "Enable lingering for podman users";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.systemd}/bin/loginctl enable-linger nginx-proxy-manager"
        "${pkgs.systemd}/bin/loginctl enable-linger emby-podman"
        "${pkgs.systemd}/bin/loginctl enable-linger media-podman"
        "${pkgs.systemd}/bin/loginctl enable-linger utils-podman"
      ];
    };
  };

  # Dedicated user for emby
  users.users.emby-podman = {
    isSystemUser = true;
    group = "media-services";
    extraGroups = [ "media-services" ];
    uid = 13105;
    home = "/var/lib/emby-podman";
    createHome = true;
    subUidRanges = [{ startUid = 200000; count = 65536; }];
    subGidRanges = [{ startGid = 200000; count = 65536; }];
  };

  # Shared user for all media services (sabnzbd, sonarr, radarr, lidarr, prowlarr)
  users.users.media-podman = {
    isSystemUser = true;
    group = "media-services";
    extraGroups = [ "media-services" ];
    uid = 13106;
    home = "/var/lib/media-podman";
    createHome = true;
    subUidRanges = [
      { startUid = 300000; count = 65536; }
    ];
    subGidRanges = [
      { startGid = 300000; count = 65536; }
    ];
  };

  # User for utility services (uptime-kuma, restic, etc)
  users.users.utils-podman = {
    isSystemUser = true;
    group = "utils-podman";
    uid = 13107;
    home = "/var/lib/utils-podman";
    createHome = true;
    subUidRanges = [
      { startUid = 400000; count = 65536; }
    ];
    subGidRanges = [
      { startGid = 400000; count = 65536; }
    ];
  };
  users.groups.utils-podman = {
    gid = 13107;
  };

  # Emby container (uses host network so NPM can reach it at localhost)
  systemd.services.emby = {
    description = "Emby Media Server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "simple";
      User = "emby-podman";
      Group = "media-services";
      UMask = "0002";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "5min";

      # Resource limits - low priority but access to all cores
      MemoryMax = "16G";   # Max 16GB RAM
      CPUWeight = 20;      # Low CPU priority (default is 100)
      IOWeight = 50;       # Low I/O priority
      Nice = 19;           # Lowest process priority

      Environment = [
        "HOME=/var/lib/emby-podman"
        "XDG_RUNTIME_DIR=/run/user/13105"
        "PATH=/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f emby"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name emby \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          --shm-size=1024m \
          --tmpfs /run \
          --tmpfs /var/run \
          -p 8096:8096 \
          -v /var/lib/emby:/config:rw \
          -v /mnt/user/Movies:/movies:ro \
          -v /mnt/user/Series:/tv:ro \
          -v /mnt/user/Music:/music:ro \
          -v /mnt/user/Backups/Emby:/backup:rw \
          --device /dev/dri:/dev/dri \
          -e PUID=0 \
          -e PGID=0 \
          -e UMASK=002 \
          -e TZ=Europe/Dublin \
          lscr.io/linuxserver/emby:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 emby";
    };
  };

  # Nginx Proxy Manager container (rootless)
  systemd.services.nginx-proxy-manager = {
    description = "Nginx Proxy Manager";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.podman pkgs.slirp4netns ];

    serviceConfig = {
      Type = "simple";
      User = "nginx-proxy-manager";
      Group = "nginx-proxy-manager";
      Restart = "always";
      RestartSec = "30min";
      TimeoutStartSec = "5min";

      Environment = [
        "HOME=/var/lib/nginx-proxy-manager"
        "XDG_RUNTIME_DIR=/run/user/13200"
        "PATH=${pkgs.slirp4netns}/bin:/run/wrappers/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f nginx-proxy-manager"
        "${pkgs.podman}/bin/podman pull docker.io/jc21/nginx-proxy-manager:latest"
      ];

      ExecStart = "${pkgs.bash}/bin/bash -c 'set -x; ${pkgs.podman}/bin/podman run --rm --name nginx-proxy-manager --label io.containers.autoupdate=registry --log-driver=journald --memory=1G --network=slirp4netns:allow_host_loopback=true -p 8102:81 -p 8002:80 -p 44302:443 -v /var/lib/npm-storage/data:/data:rw -v /var/lib/npm-storage/letsencrypt:/etc/letsencrypt:rw -e DB_SQLITE_FILE=/data/database.sqlite docker.io/jc21/nginx-proxy-manager:latest'";

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 nginx-proxy-manager";
    };
  };

  # Media services (all run under single media-podman user)
  systemd.services.sonarr = mkMediaService {
    name = "sonarr";
    port = 8989;
    volumes = [
      "/var/lib/sonarr:/config:rw"
      "/mnt/user/download:/downloads:rw"
      "/mnt/user/Series:/tv:rw"
    ];
  };

  systemd.services.radarr = mkMediaService {
    name = "radarr";
    port = 7878;
    volumes = [
      "/var/lib/radarr:/config:rw"
      "/mnt/user/download:/downloads:rw"
      "/mnt/user/Movies:/movies:rw"
    ];
  };

  systemd.services.lidarr = mkMediaService {
    name = "lidarr";
    port = 8686;
    volumes = [
      "/var/lib/lidarr:/config:rw"
      "/mnt/user/download:/downloads:rw"
      "/mnt/user/Music:/music:rw"
    ];
  };

  systemd.services.prowlarr = mkMediaService {
    name = "prowlarr";
    port = 9696;
    volumes = [
      "/var/lib/prowlarr:/config:rw"
    ];
  };

  systemd.services.lazylibrarian = mkMediaService {
    name = "lazylibrarian";
    port = 5299;
    volumes = [
      "/var/lib/lazylibrarian:/config:rw"
      "/mnt/user/Books:/books:rw"
      "/mnt/user/download:/downloads:rw"
    ];
  };

  # Uptime Kuma monitoring
  systemd.services.uptime-kuma = {
    description = "Uptime Kuma Monitoring";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.podman ];

    serviceConfig = {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "5min";

      # Resource limits
      CPUQuota = "100%";
      MemoryMax = "512M";
      IOWeight = 100;

      Environment = [
        "HOME=/var/lib/utils-podman"
        "XDG_RUNTIME_DIR=/run/user/13107"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f uptime-kuma"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name uptime-kuma \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p 3344:3001 \
          -v /var/lib/uptime-kuma:/app/data:rw \
          louislam/uptime-kuma:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 uptime-kuma";
    };
  };

  # Restic REST server for backups
  systemd.services.restic-rest-server = {
    description = "Restic REST Server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.podman ];

    serviceConfig = {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
      Restart = "always";
      RestartSec = "10s";
      TimeoutStartSec = "5min";

      # Resource limits
      CPUQuota = "100%";
      MemoryMax = "1G";
      IOWeight = 50;
      Nice = 15;

      Environment = [
        "HOME=/var/lib/utils-podman"
        "XDG_RUNTIME_DIR=/run/user/13107"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f restic-rest-server"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name restic-rest-server \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p 8000:8000 \
          -v /var/lib/restic:/data:rw \
          -e OPTIONS="--no-auth" \
          restic/rest-server:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 restic-rest-server";
    };
  };

  # Download services (all run under single media-podman user)
  systemd.services.sabnzbd = mkMediaService {
    name = "sabnzbd";
    port = 8080;
    volumes = [
      "/var/lib/sabnzbd:/config:rw"
      "/mnt/user/download:/downloads:rw"
      "/mnt/user/downloadtemp/incomplete:/incomplete-downloads:rw"
    ];
  };

  systemd.services.qbittorrent = mkMediaService {
    name = "qbittorrent";
    port = 8081;
    image = "lscr.io/linuxserver/qbittorrent:latest";
    volumes = [
      "/var/lib/qbittorrent:/config:rw"
      "/mnt/user/download:/downloads:rw"
    ];
  };

  systemd.services.deluge = mkMediaService {
    name = "deluge";
    port = 8112;
    image = "lscr.io/linuxserver/deluge:latest";
    volumes = [
      "/var/lib/deluge:/config:rw"
      "/mnt/user/download:/downloads:rw"
    ];
  };

  # Home Assistant OS VM
  systemd.services.haos-vm = {
    description = "Home Assistant OS VM";
    after = [ "network.target" "libvirtd.service" ];
    wants = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.qemu_kvm pkgs.curl pkgs.xz ];

    preStart = ''
      # Create HAOS directory if it doesn't exist
      mkdir -p /var/lib/haos

      # Download HAOS image if it doesn't exist
      if [ ! -f /var/lib/haos/haos.qcow2 ]; then
        echo "Downloading Home Assistant OS image..."
        ${pkgs.curl}/bin/curl -L -o /var/lib/haos/haos.qcow2.xz \
          https://github.com/home-assistant/operating-system/releases/download/13.2/haos_ova-13.2.qcow2.xz
        ${pkgs.xz}/bin/unxz /var/lib/haos/haos.qcow2.xz

        # Convert to compressed qcow2 and resize to 64GB
        ${pkgs.qemu_kvm}/bin/qemu-img convert -O qcow2 -c /var/lib/haos/haos.qcow2 /var/lib/haos/haos-compressed.qcow2
        mv /var/lib/haos/haos-compressed.qcow2 /var/lib/haos/haos.qcow2
        ${pkgs.qemu_kvm}/bin/qemu-img resize /var/lib/haos/haos.qcow2 64G
      fi
    '';

    serviceConfig = {
      Type = "simple";
      Restart = "always";
      RestartSec = "10s";

      ExecStart = ''
        ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 \
          -name haos \
          -machine type=q35,accel=kvm \
          -cpu host \
          -smp 2 \
          -m 4096 \
          -nographic \
          -drive file=/var/lib/haos/haos.qcow2,if=virtio,cache=writethrough,discard=on \
          -netdev user,id=net0,hostfwd=tcp::8123-:8123 \
          -device virtio-net-pci,netdev=net0 \
          -serial mon:stdio \
          -bios ${pkgs.OVMF.fd}/FV/OVMF.fd
      '';
    };
  };

  # System state version (override common config)
  system.stateVersion = lib.mkForce "25.11";
}
