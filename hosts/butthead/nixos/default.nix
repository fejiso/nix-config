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
  # Inherit quadlet containers for cross-references
  inherit (config.virtualisation.quadlet) containers;
in
{
  imports = [
    ./hardware-configuration.nix
    ../../common/nixos
    (import ../../../modules/nixos/desktop.nix)
    (import ../../../modules/nixos/systemd-nspawn.nix)
    (import ../../../modules/nixos/media-services.nix)
    (import ../../../modules/nixos/download-services.nix)
    (import ../../../modules/nixos/tdarr-worker.nix)  # imports media-podman.nix
    (import ../../../modules/nixos/development.nix)
    (import ../../../modules/nixos/tgtg-watcher.nix)
    (import ../../../modules/nixos/emulation.nix)
  ];

  # Enable Kopia server
  services.backup =
  {
    server = true;
    repoPath = "/mnt/user/Backups/Kopia";
  };

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

  # Enable Podman for containers
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    extraPackages = [ pkgs.slirp4netns ];
    autoPrune.enable = true;
  };

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

  # Quadlet container definitions
  virtualisation.quadlet.containers = {
    # Emby Media Server
    emby = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/emby:latest";
        publishPorts = [ "8096:8096" ];
        volumes = [
          "/var/lib/emby:/config:rw"
          "/mnt/user/Movies:/movies:ro"
          "/mnt/user/Series:/tv:ro"
          "/mnt/user/Music:/music:ro"
          "/mnt/user/Backups/Emby:/backup:rw"
        ];
        environments = {
          PUID = "0";
          PGID = "0";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        addDevices = [ "/dev/dri:/dev/dri" ];
        shmSize = "1024m";
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Nginx Proxy Manager
    nginx-proxy-manager = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/jc21/nginx-proxy-manager:latest";
        publishPorts = [
          "8102:81"
          "8002:80"
          "44302:443"
        ];
        volumes = [
          "/var/lib/npm-storage/data:/data:rw"
          "/var/lib/npm-storage/letsencrypt:/etc/letsencrypt:rw"
        ];
        environments = {
          DB_SQLITE_FILE = "/data/database.sqlite";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" "--memory=1G" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Sonarr - TV Series Manager
    sonarr = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/sonarr:latest";
        publishPorts = [ "8989:8989" ];
        volumes = [
          "/var/lib/sonarr:/config:rw"
          "/mnt/user/download:/downloads:rw"
          "/mnt/user/Series:/tv:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Radarr - Movie Manager
    radarr = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/radarr:latest";
        publishPorts = [ "7878:7878" ];
        volumes = [
          "/var/lib/radarr:/config:rw"
          "/mnt/user/download:/downloads:rw"
          "/mnt/user/Movies:/movies:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Lidarr - Music Manager
    lidarr = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/lidarr:latest";
        publishPorts = [ "8686:8686" ];
        volumes = [
          "/var/lib/lidarr:/config:rw"
          "/mnt/user/download:/downloads:rw"
          "/mnt/user/Music:/music:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Prowlarr - Indexer Manager
    prowlarr = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/prowlarr:latest";
        publishPorts = [ "9696:9696" ];
        volumes = [
          "/var/lib/prowlarr:/config:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # LazyLibrarian - Book Manager
    lazylibrarian = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/lazylibrarian:latest";
        publishPorts = [ "5299:5299" ];
        volumes = [
          "/var/lib/lazylibrarian:/config:rw"
          "/mnt/user/Books:/books:rw"
          "/mnt/user/download:/downloads:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # SABnzbd - Usenet Downloader
    sabnzbd = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/sabnzbd:latest";
        publishPorts = [ "8080:8080" ];
        volumes = [
          "/var/lib/sabnzbd:/config:rw"
          "/mnt/user/download:/downloads:rw"
          "/mnt/user/downloadtemp/incomplete:/incomplete-downloads:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Deluge - BitTorrent Client
    deluge = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/deluge:latest";
        publishPorts = [ "8112:8112" ];
        volumes = [
          "/var/lib/deluge:/config:rw"
          "/mnt/user/download:/downloads:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Uptime Kuma - Monitoring
    uptime-kuma = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/louislam/uptime-kuma:latest";
        publishPorts = [ "3344:3001" ];
        volumes = [
          "/var/lib/uptime-kuma:/app/data:rw"
        ];
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Restic REST Server
    restic-rest-server = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/restic/rest-server:latest";
        publishPorts = [ "8000:8000" ];
        volumes = [
          "/var/lib/restic:/data:rw"
        ];
        environments = {
          OPTIONS = "--no-auth";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Ollama LLM Runtime
    ollama = {
      autoStart = true;
      containerConfig = {
        image = "docker.io/ollama/ollama:latest";
        publishPorts = [ "11434:11434" ];
        volumes = [
          "/var/lib/ollama:/root/.ollama:rw"
        ];
        addDevices = [ "/dev/dri:/dev/dri" ];
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # Open WebUI for Ollama
    open-webui = {
      autoStart = true;
      containerConfig = {
        image = "ghcr.io/open-webui/open-webui:main";
        publishPorts = [ "3003:8080" ];
        volumes = [
          "/var/lib/open-webui:/app/backend/data:rw"
        ];
        environments = {
          OLLAMA_BASE_URL = "http://host.containers.internal:11434";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" "--add-host=host.containers.internal:host-gateway" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
      unitConfig = {
        After = [ "ollama.service" ];
        Requires = [ "ollama.service" ];
      };
    };

    # Gluetun VPN Client
    gluetun = {
      autoStart = true;
      containerConfig = {
        image = "ghcr.io/qdm12/gluetun:latest";
        publishPorts = [ "8084:8080" ];
        volumes = [
          "/var/lib/gluetun:/gluetun:rw"
        ];
        environments = {
          VPN_SERVICE_PROVIDER = "nordvpn";
          VPN_TYPE = "openvpn";
          SERVER_COUNTRIES = "Ireland";
          FIREWALL_VPN_INPUT_PORTS = "8080";
          TZ = "Europe/Dublin";
          UPDATER_PERIOD = "24h";
        };
        environmentFiles = [ "/run/secrets/nordvpn-credentials-env" ];
        addCapabilities = [ "NET_ADMIN" ];
        addDevices = [ "/dev/net/tun:/dev/net/tun" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
    };

    # qBittorrent via Gluetun VPN
    qbittorrent = {
      autoStart = true;
      containerConfig = {
        image = "lscr.io/linuxserver/qbittorrent:latest";
        network = containers.gluetun.ref;
        volumes = [
          "/var/lib/qbittorrent:/config:rw"
          "/mnt/user/download:/downloads:rw"
        ];
        environments = {
          PUID = "13106";
          PGID = "13100";
          UMASK = "002";
          TZ = "Europe/Dublin";
          WEBUI_PORT = "8080";
        };
        labels = [ "io.containers.autoupdate=registry" ];
        podmanArgs = [ "--log-driver=journald" ];
      };
      serviceConfig = {
        Restart = "always";
        RestartSec = "30";
        TimeoutStartSec = "5min";
      };
      unitConfig = {
        After = [ "gluetun.service" ];
        Requires = [ "gluetun.service" ];
      };
    };
  };

  # Create environment file for gluetun from sops secret
  systemd.services.gluetun-env-setup = {
    description = "Create Gluetun environment file from secrets";
    wantedBy = [ "multi-user.target" ];
    before = [ "gluetun.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      VPNUSER=$(sed -n "1p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
      VPNPASS=$(sed -n "2p" /run/secrets/nordvpn-credentials | tr -d "\n\r")
      echo "OPENVPN_USER=$VPNUSER" > /run/secrets/nordvpn-credentials-env
      echo "OPENVPN_PASSWORD=$VPNPASS" >> /run/secrets/nordvpn-credentials-env
      chmod 600 /run/secrets/nordvpn-credentials-env
    '';
  };

  # Enable ROCm for ML/LLM/AI workloads and create service directories
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
    "d /var/lib/nginx-proxy-manager 0755 nginx-proxy-manager nginx-proxy-manager -"
    "d /var/lib/npm-storage 0755 root root -"
    "d /var/lib/npm-storage/data 0755 root root -"
    "d /var/lib/npm-storage/letsencrypt 0755 root root -"
    "d /run/user/13200 0700 nginx-proxy-manager nginx-proxy-manager -"
    "d /run/user/13106 0700 media-podman media-services -"
    "d /run/user/13107 0700 utils-podman utils-podman -"
    "d /var/lib/ollama 0755 root root -"
    "d /var/lib/open-webui 0755 root root -"
    "d /var/lib/emby 0755 root root -"
    "d /var/lib/uptime-kuma 0755 root root -"
    "d /var/lib/restic 0755 root root -"
    # Media service directories
    "d /var/lib/sonarr 0755 13106 13100 -"
    "d /var/lib/radarr 0755 13106 13100 -"
    "d /var/lib/lidarr 0755 13106 13100 -"
    "d /var/lib/prowlarr 0755 13106 13100 -"
    "d /var/lib/lazylibrarian 0755 13106 13100 -"
    # Download service directories
    "d /var/lib/gluetun 0755 root root -"
    "d /var/lib/qbittorrent 0755 13106 13100 -"
    "d /var/lib/sabnzbd 0755 13106 13100 -"
    "d /var/lib/deluge 0755 13106 13100 -"
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
    device = "/mnt/data02:/mnt/data03:/mnt/data04:/mnt/data05:/mnt/data06";
    fsType = "fuse.mergerfs";
    options = [
      "defaults"
      "allow_other"
      "use_ino"
      "cache.files=partial"
      "dropcacheonclose=true"
      "category.create=epmfs"
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
    };
    parityFiles = [
      "/mnt/parity1/snapraid.parity"
      "/mnt/parity2/snapraid.2-parity"  # Add when sdd1 is formatted
    ];
    contentFiles = [
      "/var/snapraid/snapraid.content"
      #"/mnt/data01/.snapraid.content"  # Keep until snapraid sync removes d1 entries
      "/mnt/data02/.snapraid.content"
      "/mnt/data03/.snapraid.content"
      "/mnt/data04/.snapraid.content"
      "/mnt/data05/.snapraid.content"
      "/mnt/data06/.snapraid.content"
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
      ExecStart = "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.bash}/bin/bash ${../../../scripts/zackreed-snapraid.sh}";
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
  systemd.timers."btrfs-scrub-mnt-parity1".timerConfig.OnCalendar = lib.mkForce "*-*-25 07:00:00";
  systemd.timers."btrfs-scrub-mnt-parity2".timerConfig.OnCalendar = lib.mkForce "*-*-28 07:00:00";

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
  systemd.services."btrfs-scrub-mnt-parity1".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/parity1";
  systemd.services."btrfs-scrub-mnt-parity2".serviceConfig.ExecStart = lib.mkForce
    "${pkgs.util-linux}/bin/flock /var/lock/disk-maintenance.lock ${pkgs.btrfs-progs}/bin/btrfs scrub start -B /mnt/parity2";

  # SSD cache migration script
  systemd.services.ssd-migrate = {
    description = "Migrate old files from SSD to HDD pool";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ssd-migrate" ''
        set -e

        # Acquire exclusive lock for disk operations
        exec 200>/var/lock/disk-maintenance.lock
        ${pkgs.util-linux}/bin/flock 200

        FILELIST=$(mktemp)
        OPENFILES=$(mktemp)
        trap "rm -f $FILELIST $OPENFILES" EXIT

        # Get all open files under /mnt/data01 in one lsof call
        ${pkgs.lsof}/bin/lsof +D /mnt/data01 2>/dev/null | ${pkgs.gawk}/bin/awk 'NR>1 {print $9}' | sort -u > "$OPENFILES"

        # Build list of files to migrate (older than 24h, not open)
        while IFS= read -r -d "" file; do
          if ! grep -qxF "$file" "$OPENFILES"; then
            echo "''${file#/mnt/data01/}" >> "$FILELIST"
          fi
        done < <(${pkgs.findutils}/bin/find /mnt/data01 -type f -mtime +1 \
          ! -name "*.partial" ! -name "*.tmp" ! -path "*/.snapraid.content" ! -path "*/Trash/*" ! -path "*downloadtemp*" \
          -print0)

        if [ -s "$FILELIST" ]; then
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
        ${pkgs.util-linux}/bin/mount -o remount /mnt/user
        ${pkgs.util-linux}/bin/mount -o remount /mnt/storage
      '';
    };
  };

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

  # Home Assistant OS VM
  systemd.services.haos-vm = {
    description = "Home Assistant OS VM";
    after = [ "network.target" "libvirtd.service" ];
    wants = [ "network.target" ];
    wantedBy = [ "multi-user.target" ];

    path = [ pkgs.qemu_kvm pkgs.curl pkgs.xz ];

    unitConfig = {
      StartLimitIntervalSec = 0;
    };

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
      Restart = "always";
      RestartSec = "15min";
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
