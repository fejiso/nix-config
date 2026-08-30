{ ... }: {
  flake.modules.nixos.media-storage =
# Tiered media storage: SSD write cache (data01) in front of an HDD mergerfs
# pool, with SnapRAID parity, staggered btrfs scrubs, SSD->HDD migration and
# aggressive HDD spindown. Extracted from hosts/butthead/nixos; the disk
# layout (labels data01..data07, parity1, SSD on sdc) is butthead's.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.media-storage;

  ssd-migrate = pkgs.writeShellScript "ssd-migrate" ''
    set -e
    MODE="''${1:-daily}"

    USE_PCT=$(${pkgs.coreutils}/bin/df --output=pcent /mnt/data01 | ${pkgs.gawk}/bin/awk 'NR==2 {gsub(/%/,""); print $1+0}')

    if [ "$MODE" = "hourly" ]; then
      if [ "$USE_PCT" -lt 70 ]; then
        echo "data01 at ''${USE_PCT}% — below 70%, skipping"
        exit 0
      fi
      AGE_FLAG="-mmin +60"
    else
      AGE_FLAG="-mtime +1"
    fi
    echo "data01 at ''${USE_PCT}% — migrating files ($MODE, $AGE_FLAG)"

    # Rootless-podman quadlet services (run under the media-podman user)
    MEDIA_SERVICES="lidarr.service sonarr.service radarr.service lazylibrarian.service sabnzbd.service"
    # Native system services (tdarr is now native, not a container)
    SYSTEM_MEDIA_SERVICES="tdarr-server.service tdarr-node-*.service"

    stop_services() {
      echo "Stopping media services..."
      for svc in $MEDIA_SERVICES; do
        ${pkgs.systemd}/bin/systemctl --user -M media-podman@ stop "$svc" 2>/dev/null || true
      done
      ${pkgs.systemd}/bin/systemctl stop $SYSTEM_MEDIA_SERVICES 2>/dev/null || true
    }

    start_services() {
      echo "Starting media services..."
      for svc in $MEDIA_SERVICES; do
        ${pkgs.systemd}/bin/systemctl --user -M media-podman@ start "$svc" 2>/dev/null || true
      done
      ${pkgs.systemd}/bin/systemctl start $SYSTEM_MEDIA_SERVICES 2>/dev/null || true
    }

    # Ensure services are restarted on exit (even on failure)
    trap start_services EXIT

    # Acquire exclusive lock for disk operations
    exec 200>/var/lock/disk-maintenance.lock
    ${pkgs.util-linux}/bin/flock 200

    FILELIST=$(mktemp)
    OPENFILES=$(mktemp)
    trap "rm -f $FILELIST $OPENFILES; start_services" EXIT

    # Get all open files under /mnt/data01 in one lsof call
    ${pkgs.lsof}/bin/lsof +D /mnt/data01 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR>1 {print $9}' | sort -u > "$OPENFILES"

    # Build list of files to migrate (skip open/in-progress files)
    while IFS= read -r -d "" file; do
      if ! grep -qxF "$file" "$OPENFILES"; then
        echo "''${file#/mnt/data01/}" >> "$FILELIST"
      fi
    done < <(${pkgs.findutils}/bin/find /mnt/data01 -type f $AGE_FLAG \
      ! -name "*.partial" ! -name "*.tmp" ! -path "*/.snapraid.content" ! -path "*/Trash/*" ! -path "*downloadtemp*" \
      -print0)

    if [ -s "$FILELIST" ]; then
      stop_services
      echo "Migrating $(wc -l < "$FILELIST") files..."
      ${pkgs.rsync}/bin/rsync -av --remove-source-files --files-from="$FILELIST" /mnt/data01/ /mnt/storage/
      echo "Migration complete"
    else
      echo "No files to migrate"
    fi

    # Remove empty directories on SSD
    ${pkgs.findutils}/bin/find /mnt/data01 -type d -empty -delete 2>/dev/null || true

    # Delete files in Trash older than 7 days
    echo "Cleaning up Trash..."
    ${pkgs.findutils}/bin/find /mnt/user/Trash -type f -mtime +7 -delete 2>/dev/null || true
    ${pkgs.findutils}/bin/find /mnt/user/Trash -type d -empty -delete 2>/dev/null || true

    # Invalidate mergerfs metadata cache after moving files
    echo "Refreshing mergerfs cache..."
    ${pkgs.attr}/bin/setfattr -n user.mergerfs.cache.clear -v true /mnt/user/.mergerfs 2>/dev/null || true
    ${pkgs.attr}/bin/setfattr -n user.mergerfs.cache.clear -v true /mnt/storage/.mergerfs 2>/dev/null || true
  '';
in
{
  options.services.media-storage = {
    enable = mkEnableOption "tiered SSD/HDD media storage with SnapRAID";
  };

  config = mkIf cfg.enable {
    # Storage configuration for media server
    # Individual data disk mounts
    fileSystems."/mnt/data01" = {
      device = "/dev/disk/by-label/data01"; # sdc1 - 953.9G
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data02" = {
      device = "/dev/disk/by-label/data02"; # sda1 - 3.6T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data03" = {
      device = "/dev/disk/by-label/data03"; # sdb1 - 3.6T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data04" = {
      device = "/dev/disk/by-label/data04"; # sde1 - 3.6T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data05" = {
      device = "/dev/disk/by-label/data05"; # sdf1 - 7.3T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data06" = {
      device = "/dev/disk/by-label/data06"; # sdh1 - 3.6T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    fileSystems."/mnt/data07" = {
      device = "/dev/disk/by-label/data07";
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };

    # Parity disk mounts
    fileSystems."/mnt/parity1" = {
      device = "/dev/disk/by-label/parity1"; # sdg1 - 7.3T
      fsType = "btrfs";
      options = [ "defaults" "noatime" "nofail" "compress=zstd" ];
    };


    # MergerFS pool combining all data disks (SSD writes first)
    fileSystems."/mnt/user" = {
      # bcachefs appended temporarily during mergerfs/snapraid -> bcachefs migration
      device = "/mnt/data01:/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06:/mnt/data07:/mnt/bcachefs";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=ff"
        # Metadata caching (3h) to prevent drive spinup
        "cache.symlinks=true"
        "cache.readdir=true"
        "cache.attr=10800"
        "cache.entry=10800"
        "cache.negative_entry=300"
        "cache.statfs=10800"
      ];
    };

    # Slow storage pool (HDDs only, for aging files from SSD)
    fileSystems."/mnt/storage" = {
      device = "/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06:/mnt/data07";
      fsType = "fuse.mergerfs";
      options = [
        "defaults"
        "allow_other"
        "use_ino"
        "cache.files=partial"
        "dropcacheonclose=true"
        "category.create=mfs"
        # Metadata caching (3h) to prevent drive spinup
        "cache.symlinks=true"
        "cache.readdir=true"
        "cache.attr=10800"
        "cache.entry=10800"
        "cache.negative_entry=300"
        "cache.statfs=10800"
      ];
    };

    # SnapRAID configuration
    services.snapraid = {
      enable = true;
      dataDisks = {
        #d1 = "/mnt/data01";  # Keep until snapraid sync removes its entries
        d2 = "/mnt/data02";
        d3 = "/mnt/data03";
        d4 = "/mnt/data04";
        d5 = "/mnt/data05";
        d6 = "/mnt/data06";
        d7 = "/mnt/data07";
      };
      parityFiles = [
        "/mnt/parity1/snapraid.parity"
      ];
      contentFiles = [
        "/var/snapraid/snapraid.content"
        #"/mnt/data01/.snapraid.content"  # Keep until snapraid sync removes d1 entries
        "/mnt/data02/.snapraid.content"
        "/mnt/data03/.snapraid.content"
        "/mnt/data04/.snapraid.content"
        "/mnt/data05/.snapraid.content"
        "/mnt/data06/.snapraid.content"
        "/mnt/data07/.snapraid.content"
      ];
    };

    # Disable the NixOS snapraid module's built-in timers
    systemd.timers.snapraid-sync.enable = lib.mkForce false;
    systemd.timers.snapraid-scrub.enable = lib.mkForce false;

    # SnapRAID maintenance via zackreed script (replaces built-in sync/scrub)
    # Runs after ssd-migrate to ensure files are settled before parity sync
    systemd.services.snapraid-maintenance = {
      description = "SnapRAID maintenance (diff/sync/scrub/SMART)";
      after = [ "local-fs.target" "ssd-migrate.service" ];
      wants = [ "ssd-migrate.service" ];
      path = with pkgs; [ snapraid curl coreutils gawk gnused gnugrep inetutils util-linux findutils ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.bash}/bin/bash ${../../scripts/zackreed-snapraid.sh}";
        ExecStartPost = "${pkgs.bash}/bin/bash -c '${pkgs.curl}/bin/curl -fsS -o /dev/null \"$(cat ${config.sops.secrets.kuma-disk-maintenance-push-url.path})\"'";
        StandardOutput = "append:/var/log/snapraid-run.log";
        StandardError = "append:/var/log/snapraid-run.log";
        Nice = 19;
        IOSchedulingPriority = 7;
        CPUSchedulingPolicy = "batch";
      };
    };

    systemd.timers.snapraid-maintenance = {
      description = "Daily SnapRAID maintenance at 4am";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "04:00";
        Persistent = true;
      };
    };

    # Override autoScrub timers with staggered schedules for data/parity drives
    systemd.timers."btrfs-scrub-mnt-data01".timerConfig.OnCalendar = lib.mkForce "*-*-01 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data02".timerConfig.OnCalendar = lib.mkForce "*-*-05 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data03".timerConfig.OnCalendar = lib.mkForce "*-*-09 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data04".timerConfig.OnCalendar = lib.mkForce "*-*-13 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data05".timerConfig.OnCalendar = lib.mkForce "*-*-17 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data06".timerConfig.OnCalendar = lib.mkForce "*-*-21 07:00:00";
    systemd.timers."btrfs-scrub-mnt-data07".timerConfig.OnCalendar = lib.mkForce "*-*-23 07:00:00";
    systemd.timers."btrfs-scrub-mnt-parity1".timerConfig.OnCalendar = lib.mkForce "*-*-25 07:00:00";

    # Wrap scrub services with flock to guarantee no two scrubs run simultaneously
    systemd.services."btrfs-scrub-mnt-data01".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data01";
    systemd.services."btrfs-scrub-mnt-data02".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data02";
    systemd.services."btrfs-scrub-mnt-data03".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data03";
    systemd.services."btrfs-scrub-mnt-data04".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data04";
    systemd.services."btrfs-scrub-mnt-data05".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data05";
    systemd.services."btrfs-scrub-mnt-data06".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data06";
    systemd.services."btrfs-scrub-mnt-data07".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/data07";
    systemd.services."btrfs-scrub-mnt-parity1".serviceConfig.ExecStart = lib.mkForce
      "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/parity1";

    # SSD cache migration services
    #   ssd-migrate:         daily, always runs, migrates files older than 24h (triggered by snapraid)
    #   ssd-migrate-hourly:  hourly, only if data01 > 70% full, migrates files older than 1h
    systemd.services.ssd-migrate = {
      description = "Migrate old files from SSD to HDD pool (daily)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ssd-migrate} daily";
      };
    };

    systemd.services.ssd-migrate-hourly = {
      description = "Migrate old files from SSD to HDD pool (hourly)";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${ssd-migrate} hourly";
      };
    };

    systemd.timers.ssd-migrate-hourly = {
      description = "Hourly SSD cache migration";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
      };
    };

    # Download + SnapRAID working directories
    systemd.tmpfiles.rules = [
      # Download directories with proper permissions
      "d /mnt/user/download 0775 root media-services -"
      "d /mnt/user/downloadtemp 0775 root media-services -"
      "d /mnt/user/downloadtemp/incomplete 0775 root media-services -"
      # SnapRAID directories
      "d /var/snapraid 0755 root root -"
      "d /var/log/snapraid 0755 root root -"
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

    # Storage and filesystem tools
    environment.systemPackages = with pkgs; [
      mergerfs
      mergerfs-tools
      snapraid
      hdparm
    ];
  };
}
;
}
