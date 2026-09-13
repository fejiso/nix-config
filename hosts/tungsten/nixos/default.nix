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
  ];

  # ADS-B configuration (Hardware support only)
  services.adsb-readsb = {
    enable = false;
    enableRtlSdrHardware = true;
  };

  # Enable development tools
  development.enable = true;

  # Enable emulation
  emulation.enable = true;

  # ThinkPad P16 Gen 2: use power-profiles-daemon instead of TLP
  services.power-profiles-daemon.enable = lib.mkForce true;
  services.tlp.enable = lib.mkForce false;
  systemd.services.power-saver-default = {
    description = "Set default power profile to power-saver";
    after = [ "power-profiles-daemon.service" ];
    requires = [ "power-profiles-daemon.service" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set power-saver";
    };
  };

  # The 100MB ESP (nvme0n1p2) is shared with the legacy Windows install and
  # cannot hold kernel+initrd when the initrd carries the 15MB Intel microcode
  # early-cpio. Rely on BIOS-level microcode instead (keep BIOS/firmware
  # updated via fwupd/LVFS).
  hardware.cpu.intel.updateMicrocode = lib.mkForce false;

  # Intel wifi (iwlwifi/iwlmvm) fails to connect with power saving enabled.
  # Disable power saving at both the NetworkManager and driver level.
  networking.networkmanager.wifi.powersave = false;
  boot.extraModprobeConfig = ''
    options iwlwifi power_save=0
    options iwlmvm power_scheme=1
  '';

  # Hybrid graphics: Intel iGPU + NVIDIA RTX 3500 Ada (PRIME render offload)
  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.graphics.enable = true;
  hardware.nvidia = {
    modesetting.enable = true;
    open = true; # Ada Lovelace requires the open kernel modules
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    nvidiaSettings = true;
    prime = {
      offload.enable = true;
      offload.enableOffloadCmd = true; # provides `nvidia-offload <cmd>`
      # Verify with: lspci | grep -E 'VGA|3D'
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";
    };
  };

  # Boot configuration
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.initrd.systemd.enable = true;
  boot.initrd.compressor = "xz";
  boot.initrd.luks.devices."cryptroot" = {
    device = "/dev/disk/by-uuid/7f1bd4db-58b3-40aa-be5c-d38ba434cfcb";
  };
  boot.loader.systemd-boot.configurationLimit = 1;
  boot.resumeDevice = "/dev/disk/by-uuid/54cc1038-6f3b-49c0-925b-81ad8127d045";
  boot.kernelParams = [ "resume_offset=533760" ];

  # Swap configuration
  swapDevices = [
    {
      device = "/swapfile";
      size = 18432; # 18GB in MB
    }
  ];

  # Host-specific networking
  networking.hostName = "tungsten";

  # Tdarr worker node (native NixOS service)
  services.tdarr-worker = {
    enable = true;
  };

  # System state version
  system.stateVersion = "25.05";

  # llama.cpp RPC worker for hierro's distributed inference master (CPU only)
  services.llama-rpc.worker.enable = true;
}
