# EliteDX specific NixOS configuration
{
  inputs,
  outputs,
  lib,
  config,
  pkgs,
  ...
}: {
  imports = [
    ./hardware-configuration.nix
    (import ../../../modules/nixos/emulation.nix)
  ];

  # Enable emulation
  emulation.enable = true;

  # Host-specific configuration
  # Add desktop environment if this is a desktop system
  services.xserver = {
    enable = true;
    resolutions = [
      {
        x = 1920;
        y = 1080;
      }
      {
        x = 1280;
        y = 720;
      }
    ];
    videoDrivers = ["amdgpu"];
    displayManager.startx.enable = true;
    displayManager.session = [
      {
        manage = "desktop";
        name = "RetroArch";
        start = ''
          ${pkgs.retroarch-full}/bin/retroarch --fullscreen &
          waitPID=$!
        '';
      }
    ];
  };
  services.displayManager.defaultSession = "RetroArch";
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "z-247";

  
  
  # Host-specific packages
  environment.systemPackages = with pkgs; [
    libva-utils
    lightdm
    xorg.xinit
    cifs-utils
    lm_sensors
    nvme-cli
    smartmontools
    intel-gpu-tools
  ];

  # NFS mounts for ROMs, Saves and BIOS
  fileSystems."/home/z-247/ROMs/ROMS" = {
    device = "10.2.3.200:/mnt/user/ROMs/Clean";
    fsType = "nfs";
    options = [ "nfsvers=4" "noatime" "x-systemd.automount" "nofail" "fsc" "_netdev" "rw" ];
  };
  fileSystems."/home/z-247/ROMs/SAVES" = {
    device = "10.2.3.200:/mnt/user/ROMs/Saves";
    fsType = "nfs";
    options = [ "nfsvers=4" "noatime" "x-systemd.automount" "nofail" "fsc" "_netdev" "rw" ];
  };
  fileSystems."/home/z-247/ROMs/BIOS" = {
    device = "10.2.3.200:/mnt/user/ROMs/BIOS";
    fsType = "nfs";
    options = [ "nfsvers=4" "noatime" "x-systemd.automount" "nofail" "fsc" "_netdev" "rw" ];
  };

  # Pipewire configuration
  security.rtkit.enable = true;
  services.avahi.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
    wireplumber.enable = true;
    raopOpenFirewall = true;
    extraConfig.pipewire = {
      "10-airplay" = {
        "context.modules" = [
          {
            name = "libpipewire-module-raop-discover";
          }
        ];
      };
    };
  };

  # Filesystem caching
  boot.kernelModules = ["fscache"];
  services.cachefilesd = {
    enable = true;
    cacheDir = "/var/cache/fscache";
    extraConfig = ''
      brun 15%
      bcull 10%
      bstop 5%
      frun 15%
      fcull 10%
      fstop 5%
    '';
  };
  fileSystems."/var/cache/fscache" = {
    device = "/dev/disk/by-uuid/50858290-1962-4378-944c-a9c0f50fd720";
    fsType = "btrfs";
    options = ["compress=zstd"];
  };

}
