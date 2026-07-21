{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  hostname,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
  ];

  # Enable quadlet-based containers
  services.quadlet-media.enable = true;
  services.quadlet-utils.enable = true;

  # Enable Kopia server
  services.backup = {
    server = true;
    repoPath = "/mnt/user/Backups/Kopia";
    # Every NixOS host backs up /home + /var/lib here. Each is registered as
    # backup-user@<hostname> by kopia-register-clients. butthead itself snapshots
    # via localhost (see backup.nix), so it must be registered here too.
    clients = [
      "elitedex" "lenovix" "hispanas" "a8" "blacktop" "hierro" "butthead" "snuffles"
      "rpi3" "pine64" "xpi-s905x3" "z-turn" "kr260"
    ];
  };

  # Enable development tools
  development.enable = true;

  # Enable emulation
  emulation.enable = true;

  # Tiered SSD/HDD media storage (mergerfs + SnapRAID + ssd-migrate)
  services.media-storage.enable = true;

  # Nginx Proxy Manager (rootless podman)
  services.nginx-proxy-manager.enable = true;

  # Home Assistant OS VM
  services.haos-vm.enable = true;

  # SANE scanner support
  hardware.sane = {
    enable = true;
    extraBackends = [ pkgs.sane-airscan ];
  };

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

  # SoundCork — local Bose SoundTouch cloud replacement (unlocks the SoundTouch
  # 30 after Bose's cloud shutdown). Module: flake-modules/system-modules/soundcork.nix.
  # Set baseUrl to butthead's LAN IP if the speaker can't resolve "butthead".
  services.soundcork.enable = true;

  # Enable Podman for nginx-proxy-manager
  virtualisation.podman = {
    enable = true;
    dockerCompat = false;
    extraPackages = [ pkgs.slirp4netns ];
    autoPrune.enable = true;
  };

  # Use podman for oci-containers
  virtualisation.oci-containers.backend = "podman";

  # Docker daemon — standard docker/docker-compose workflow (user in docker group)
  virtualisation.docker = {
    enable = true;
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

  # Enable ROCm for ML/LLM/AI workloads
  systemd.tmpfiles.rules = [
    "L+    /opt/rocm/hip   -    -    -     -    ${pkgs.rocmPackages.clr}"
  ];

  # AMD GPU (RX 500 series / Polaris / gfx803)
  # NVIDIA GPU (EVGA 3060 12GB) for ML workloads
  services.xserver.videoDrivers = [ "amdgpu" "nvidia" ];

  hardware.nvidia = {
    modesetting.enable = true;
    open = true;  # Ampere (GA106) supports open kernel modules
    nvidiaSettings = true;
    # Use the nixpkgs default (stable) driver so the userspace EGL/GLX stack
    # tracks the rest of nixpkgs instead of being frozen at an old version.
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      rocmPackages.clr.icd
    ];
  };

  # NVIDIA Container Toolkit (CDI) — GPU access in Docker & Podman containers
  hardware.nvidia-container-toolkit.enable = true;

  # ROCm on pre-Vega: override GFX version to gfx803 and limit HW queues for stability
  environment.variables = {
    HSA_OVERRIDE_GFX_VERSION = "8.0.3";
    GPU_MAX_HW_QUEUES = "1";
  };

  # Tdarr requires identical /mnt/* paths on the server and every node.
  # butthead owns the NFS exports, so expose the local mergerfs directories via
  # bind mounts instead of NFS-mounting butthead's own Netbird address.
  fileSystems = {
    "/mnt/Series" = lib.mkForce {
      device = "/mnt/user/Series";
      fsType = "none";
      options = [ "bind" "rw" ];
      depends = [ "/mnt/user" ];
    };

    "/mnt/Movies" = lib.mkForce {
      device = "/mnt/user/Movies";
      fsType = "none";
      options = [ "bind" "rw" ];
      depends = [ "/mnt/user" ];
    };

    "/mnt/downloadtemp" = lib.mkForce {
      device = "/mnt/user/downloadtemp";
      fsType = "none";
      options = [ "bind" "rw" ];
      depends = [ "/mnt/user" ];
    };
  };

  # Tdarr transcoding server and worker (native NixOS services).
  # Uses the unified /mnt/* paths shared (identically) across all nodes.
  services.tdarr-worker = {
    enable = true;
    serverEnabled = true;
  };

  # Additional packages for media server functionality
  environment.systemPackages = with pkgs; [
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

    # NVIDIA/CUDA for ML/AI
    nvtopPackages.nvidia
    cudaPackages.cudatoolkit

    # Docker/container tools
    docker-compose
    podman-compose

    # Scanning
    simple-scan
  ];

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
    allowedTCPPorts = [ 2049 111 20048 8102 8002 44302 3002 4743 8096 8080 8989 7878 8686 9696 5299 8081 8112 3344 8000 8010 11434 3003 8084 6080 8188 29999 30000 30001 30002 30003 30004 30005 30006 30007 30008 30009 ];
    allowedUDPPorts = [ 2049 111 20048 ];
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

  # System state version (override base default)
  system.stateVersion = lib.mkForce "25.11";
}
