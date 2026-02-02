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
  # Common restart configuration for all podman services (serviceConfig)
  commonRestartConfig = {
    Restart = "always";
    RestartSec = "15min";
  };

  # Common unit configuration for all podman services
  commonUnitConfig = {
    StartLimitIntervalSec = 0;
  };

  # Helper function to create media service configurations
  mkMediaService = { name, port, volumes, image ? "lscr.io/linuxserver/${name}:latest" }: {
    description = lib.strings.toUpper (lib.substring 0 1 name) + lib.substring 1 (lib.stringLength name) name;
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.podman ];

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "media-podman";
      Group = "media-services";
      UMask = "0002";
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
          --userns=keep-id:uid=13106,gid=13100 \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p ${toString port}:${toString port} \
          ${lib.concatMapStringsSep " " (v: "-v ${v}") volumes} \
          -e PUID=13106 \
          -e PGID=13100 \
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
    (import ../../../modules/nixos/tdarr-worker.nix)
    (import ../../../modules/nixos/development.nix)
    (import ../../../modules/nixos/tgtg-watcher.nix)
    (import ../../../modules/nixos/emulation.nix)
  ];

  # Enable Kopia server
  services.backup.server = true;

  # Enable development tools
  development.enable = true;

  # Enable emulation
  emulation.enable = true;

  # Enable TooGoodToGo watcher
  services.tgtg-watcher.enable = true;

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";

  # Swap configuration with hibernation support
  swapDevices = [{
    device = "/swapfile";
  }];

  # Hibernation configuration
  boot.resumeDevice = "/dev/disk/by-uuid/2ae17721-d56e-4707-90af-9d17b37a14c7";
  boot.kernelParams = [ "resume_offset=3987983" ];

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
    "d /run/user/13106 0700 media-podman media-services -"
    "d /run/user/13107 0700 utils-podman utils-podman -"
    "d /var/lib/ollama 0755 utils-podman utils-podman -"
    "d /var/lib/open-webui 0755 utils-podman utils-podman -"
    # Media service directories
    "d /var/lib/sonarr 0755 media-podman media-services -"
    "d /var/lib/radarr 0755 media-podman media-services -"
    "d /var/lib/lidarr 0755 media-podman media-services -"
    "d /var/lib/prowlarr 0755 media-podman media-services -"
    "d /var/lib/lazylibrarian 0755 media-podman media-services -"
    # Download service directories
    "d /var/lib/gluetun 0755 media-podman media-services -"
    "d /var/lib/qbittorrent 0755 media-podman media-services -"
    "d /var/lib/sabnzbd 0755 media-podman media-services -"
    "d /var/lib/deluge 0755 media-podman media-services -"
    # Download directories with proper permissions
    "d /mnt/user/download 0775 root media-services -"
    "d /mnt/user/downloadtemp 0775 root media-services -"
    "d /mnt/user/downloadtemp/incomplete 0775 root media-services -"
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
    options = [ "defaults" "noatime" "nofail" ];
  };

  fileSystems."/mnt/data02" = {
    device = "/dev/disk/by-label/data02"; # sda1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  fileSystems."/mnt/data03" = {
    device = "/dev/disk/by-label/data03"; # sdb1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  fileSystems."/mnt/data04" = {
    device = "/dev/disk/by-label/data04"; # sde1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  fileSystems."/mnt/data05" = {
    device = "/dev/disk/by-label/data05"; # sdf1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  fileSystems."/mnt/data06" = {
    device = "/dev/disk/by-label/data06"; # sdh1 - 3.6T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  # Parity disk mounts
  fileSystems."/mnt/parity1" = {
    device = "/dev/disk/by-label/parity1"; # sdg1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
  };

  # Parity2
  fileSystems."/mnt/parity2" = {
    device = "/dev/disk/by-label/parity2"; # sdd1 - 7.3T
    fsType = "btrfs";
    options = [ "defaults" "noatime" "nofail" ];
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

    # Sync configuration - DISABLED during backup restore to preserve parity
    # sync.interval = "04:00";  # Daily sync at 4am
  };

  # Override autoScrub timers with staggered schedules for data/parity drives
  systemd.timers."btrfs-scrub-mnt-data01".timerConfig.OnCalendar = lib.mkForce "*-*-01 02:00:00";
  systemd.timers."btrfs-scrub-mnt-data02".timerConfig.OnCalendar = lib.mkForce "*-*-05 02:00:00";
  systemd.timers."btrfs-scrub-mnt-data03".timerConfig.OnCalendar = lib.mkForce "*-*-09 02:00:00";
  systemd.timers."btrfs-scrub-mnt-data04".timerConfig.OnCalendar = lib.mkForce "*-*-13 02:00:00";
  systemd.timers."btrfs-scrub-mnt-data05".timerConfig.OnCalendar = lib.mkForce "*-*-17 02:00:00";
  systemd.timers."btrfs-scrub-mnt-data06".timerConfig.OnCalendar = lib.mkForce "*-*-21 02:00:00";
  systemd.timers."btrfs-scrub-mnt-parity1".timerConfig.OnCalendar = lib.mkForce "*-*-25 02:00:00";
  systemd.timers."btrfs-scrub-mnt-parity2".timerConfig.OnCalendar = lib.mkForce "*-*-28 02:00:00";

  # Wrap scrub services with flock to guarantee no two scrubs run simultaneously
  systemd.services."btrfs-scrub-mnt-data01".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data01";
  systemd.services."btrfs-scrub-mnt-data02".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data02";
  systemd.services."btrfs-scrub-mnt-data03".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data03";
  systemd.services."btrfs-scrub-mnt-data04".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data04";
  systemd.services."btrfs-scrub-mnt-data05".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data05";
  systemd.services."btrfs-scrub-mnt-data06".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data06";
  systemd.services."btrfs-scrub-mnt-parity1".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/parity1";
  systemd.services."btrfs-scrub-mnt-parity2".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/btrfs-scrub.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/parity2";

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
    wantedBy = []; # disabled
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

  # Tdarr transcoding server and worker
  services.tdarr-worker = {
    enable = true;
    serverEnabled = true;
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
      /mnt/user/Series 100.107.0.0/16(rw,sync,no_subtree_check,fsid=1)
      /mnt/user/Movies 100.107.0.0/16(rw,sync,no_subtree_check,fsid=6)
      /mnt/user/Videos 100.107.0.0/16(ro,sync,no_subtree_check,fsid=2)
      /mnt/user/Music 100.107.0.0/16(ro,sync,no_subtree_check,fsid=3) 100.107.6.184(rw,sync,no_subtree_check,fsid=3) 100.107.75.195(rw,sync,no_subtree_check,fsid=3) 100.107.206.129(rw,sync,no_subtree_check,fsid=3)
      /mnt/user/ROMs 100.107.0.0/16(ro,sync,no_subtree_check,fsid=4)
      /mnt/user/Backups 100.107.0.0/16(rw,sync,no_subtree_check,fsid=5)
      /mnt/user/downloadtemp 100.107.0.0/16(rw,sync,no_subtree_check,fsid=7)
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
    allowedTCPPorts = [ 2049 111 20048 8102 8002 44302 3002 4743 8096 8080 8989 7878 8686 9696 5299 8081 8112 3344 8000 11434 3003 8084 ];
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

  # Shared group for media services - defined in tdarr-worker.nix
  # users.groups.media-services = {
  #   gid = 13100;
  # };

  # Enable lingering for podman users to create /run/user/UID directories
  systemd.services.enable-linger-podman-users = {
    description = "Enable lingering for podman users";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = [
        "${pkgs.systemd}/bin/loginctl enable-linger nginx-proxy-manager"
        "${pkgs.systemd}/bin/loginctl enable-linger media-podman"
        "${pkgs.systemd}/bin/loginctl enable-linger utils-podman"
      ];
    };
  };

  # Emby now uses media-podman user like other media services
  # users.users.emby-podman = {
  #   isSystemUser = true;
  #   group = "media-services";
  #   extraGroups = [ "media-services" ];
  #   uid = 13105;
  #   home = "/var/lib/emby-podman";
  #   createHome = true;
  #   subUidRanges = [{ startUid = 200000; count = 65536; }];
  #   subGidRanges = [{ startGid = 200000; count = 65536; }];
  # };

  # Shared user for all media services - defined in tdarr-worker.nix
  # users.users.media-podman = {
  #   isSystemUser = true;
  #   group = "media-services";
  #   extraGroups = [ "media-services" ];
  #   uid = 13106;
  #   home = "/var/lib/media-podman";
  #   createHome = true;
  #   subUidRanges = [
  #     { startUid = 300000; count = 65536; }
  #   ];
  #   subGidRanges = [
  #     { startGid = 300000; count = 65536; }
  #   ];
  # };

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

  # Emby container
  systemd.services.emby = {
    description = "Emby Media Server";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "media-podman";
      Group = "media-services";
      UMask = "0002";
      TimeoutStartSec = "5min";

      # Resource limits - low priority but access to all cores
      MemoryMax = "16G";   # Max 16GB RAM
      CPUWeight = 20;      # Low CPU priority (default is 100)
      IOWeight = 50;       # Low I/O priority
      Nice = 19;           # Lowest process priority

      Environment = [
        "HOME=/var/lib/media-podman"
        "XDG_RUNTIME_DIR=/run/user/13106"
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

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "nginx-proxy-manager";
      Group = "nginx-proxy-manager";
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

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
      TimeoutStartSec = "5min";

      # Resource limits
      CPUQuota = "100%";
      MemoryMax = "512M";
      IOWeight = 100;

      # Capture stderr/stdout
      StandardOutput = "journal";
      StandardError = "journal";

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
          docker.io/louislam/uptime-kuma:latest
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

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
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
          docker.io/restic/rest-server:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 restic-rest-server";
    };
  };

  # Ollama LLM runtime
  systemd.services.ollama = {
    description = "Ollama LLM Runtime";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
      TimeoutStartSec = "5min";

      # Resource limits - needs more resources for LLMs
      MemoryMax = "16G";
      IOWeight = 50;

      # Capture stderr/stdout
      StandardOutput = "journal";
      StandardError = "journal";

      Environment = [
        "HOME=/var/lib/utils-podman"
        "XDG_RUNTIME_DIR=/run/user/13107"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f ollama"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name ollama \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p 11434:11434 \
          -v /var/lib/ollama:/root/.ollama:rw \
          --device /dev/dri:/dev/dri \
          docker.io/ollama/ollama:latest
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 30 ollama";
    };
  };

  # Open WebUI for Ollama
  systemd.services.open-webui = {
    description = "Open WebUI for Ollama";
    after = [ "network-online.target" "ollama.service" ];
    wants = [ "network-online.target" ];
    requires = [ "ollama.service" ];
    wantedBy = [ "multi-user.target" ];

    unitConfig = commonUnitConfig;

    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "utils-podman";
      Group = "utils-podman";
      TimeoutStartSec = "5min";

      # Resource limits
      CPUQuota = "200%";
      MemoryMax = "4G";
      IOWeight = 100;

      # Capture stderr/stdout
      StandardOutput = "journal";
      StandardError = "journal";

      Environment = [
        "HOME=/var/lib/utils-podman"
        "XDG_RUNTIME_DIR=/run/user/13107"
        "PATH=/run/wrappers/bin:/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin"
      ];

      ExecStartPre = [
        "-${pkgs.podman}/bin/podman rm -f open-webui"
      ];

      ExecStart = ''
        ${pkgs.podman}/bin/podman run --rm --name open-webui \
          --label io.containers.autoupdate=registry \
          --log-driver=journald \
          -p 3003:8080 \
          -v /var/lib/open-webui:/app/backend/data:rw \
          --add-host=host.containers.internal:host-gateway \
          -e OLLAMA_BASE_URL=http://host.containers.internal:11434 \
          ghcr.io/open-webui/open-webui:main
      '';

      ExecStop = "${pkgs.podman}/bin/podman stop -t 10 open-webui";
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

  # Gluetun VPN Service
  systemd.services.gluetun = {
    description = "Gluetun VPN Client";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman ];
    unitConfig = commonUnitConfig;
    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "media-podman";
      Group = "media-services";
      TimeoutStartSec = "5min";
      
      # Resource limits
      CPUQuota = "100%";
      MemoryMax = "1G";

      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f gluetun";
      
      ExecStart = pkgs.writeShellScript "start-gluetun" ''
        VPNUSER=$(sed -n "1p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
        VPNPASS=$(sed -n "2p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
        ${pkgs.podman}/bin/podman run --rm --name gluetun \
          --cap-add=NET_ADMIN \
          --device=/dev/net/tun:/dev/net/tun \
          -p 8084:8080 \
          -v /var/lib/gluetun:/gluetun:rw \
          -e VPN_SERVICE_PROVIDER=nordvpn \
          -e VPN_TYPE=openvpn \
          -e OPENVPN_USER="$VPNUSER" \
          -e OPENVPN_PASSWORD="$VPNPASS" \
          -e SERVER_COUNTRIES=Ireland \
          -e FIREWALL_VPN_INPUT_PORTS=8080 \
          -e TZ=Europe/Dublin \
          -e UPDATER_PERIOD=24h \
          ghcr.io/qdm12/gluetun:latest
      '';
      
      ExecStop = "${pkgs.podman}/bin/podman stop gluetun";
    };
  };

  # qBittorrent Service (via Gluetun)
  systemd.services.qbittorrent = {
    description = "qBittorrent (via Gluetun)";
    requires = [ "gluetun.service" ];
    after = [ "gluetun.service" ];
    wantedBy = [ "multi-user.target" ];
    path = [ pkgs.podman pkgs.gnused pkgs.coreutils ];
    unitConfig = commonUnitConfig;
    serviceConfig = commonRestartConfig // {
      Type = "simple";
      User = "media-podman";
      Group = "media-services";
      TimeoutStartSec = "5min";
      
      # Resource limits
      CPUQuota = "200%";
      MemoryMax = "3G";

      ExecStartPre = "-${pkgs.podman}/bin/podman rm -f qbittorrent";
      
      ExecStart = pkgs.writeShellScript "start-qbittorrent" ''
        # Wait for Gluetun container to be ready
        until ${pkgs.podman}/bin/podman inspect gluetun >/dev/null 2>&1; do 
          echo "Waiting for gluetun container..."
          sleep 1
        done

        # Ensure config
        CONF_FILE="/var/lib/qbittorrent/qBittorrent/qBittorrent.conf"
        mkdir -p "$(dirname "$CONF_FILE")"
        
        if [ ! -f "$CONF_FILE" ]; then
            echo -e "[Preferences]\nWebUI\\HostHeaderValidation=false\nWebUI\\CSRFProtection=false" > "$CONF_FILE"
        else
            # Ensure [Preferences] section exists
            if ! grep -q "^\[Preferences\]" "$CONF_FILE"; then
                echo "[Preferences]" >> "$CONF_FILE"
            fi
            
            # Set HostHeaderValidation
            if grep -q "WebUI\\\\HostHeaderValidation" "$CONF_FILE"; then
                sed -i 's/WebUI\\HostHeaderValidation=.*/WebUI\\HostHeaderValidation=false/' "$CONF_FILE"
            else
                sed -i '/^\[Preferences\]/a WebUI\\HostHeaderValidation=false' "$CONF_FILE"
            fi
            
            # Set CSRFProtection
            if grep -q "WebUI\\\\CSRFProtection" "$CONF_FILE"; then
                sed -i 's/WebUI\\CSRFProtection=.*/WebUI\\CSRFProtection=false/' "$CONF_FILE"
            else
                sed -i '/^\[Preferences\]/a WebUI\\CSRFProtection=false' "$CONF_FILE"
            fi
        fi

        ${pkgs.podman}/bin/podman run --rm --name qbittorrent \
          --userns=keep-id:uid=13106,gid=13100 \
          --network container:gluetun \
          --label io.containers.autoupdate=registry \
          -v /var/lib/qbittorrent:/config:rw \
          -v /mnt/user/download:/downloads:rw \
          -e PUID=13106 \
          -e PGID=13100 \
          -e UMASK=002 \
          -e TZ=Europe/Dublin \
          -e WEBUI_PORT=8080 \
          lscr.io/linuxserver/qbittorrent:latest
      '';
      
      ExecStop = "${pkgs.podman}/bin/podman stop qbittorrent";
    };
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

    unitConfig = commonUnitConfig;

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

    serviceConfig = commonRestartConfig // {
      Type = "simple";

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
