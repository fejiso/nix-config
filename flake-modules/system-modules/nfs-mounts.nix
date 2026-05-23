{ ... }: {
  flake.modules.nixos.nfs-mounts =
{ config, lib, pkgs, ... }:

with lib;

{
  options = {
    services.nfs-mounts = {
      enable = mkEnableOption "NFS mounts";
    };
  };

  config = mkIf config.services.nfs-mounts.enable {
    # Enable NFS client support
    services.rpcbind.enable = true;
    
    # Create mount points
    systemd.tmpfiles.rules = [
      "d /mnt/Series 0755 root root -"
      "d /mnt/Movies 0755 root root -"
      "d /mnt/Backups 0755 root root -"
      "d /mnt/Videos 0755 root root -"
      "d /mnt/Music 0755 root root -"
      "d /mnt/ROMs 0755 root root -"
      "d /mnt/downloadtemp 0755 root root -"
    ];

    # NFS mounts
    fileSystems = {
      "/mnt/Series" = {
        device = "100.107.75.195:/mnt/user/Series";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "async"
          "rw"
          "intr"
          "hard"
          "vers=4"
          "noauto"
        ];
      };

      "/mnt/Movies" = {
        device = "100.107.75.195:/mnt/user/Movies";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "async"
          "rw"
          "intr"
          "hard"
          "vers=4"
          "noauto"
        ];
      };

      "/mnt/Backups" = {
        device = "100.107.75.195:/mnt/user/Backups";
        fsType = "nfs";
        options = [
          "rw"
          "hard"
          "x-systemd.automount"
          "x-systemd.idle-timeout=60s"
          "noauto"
        ];
      };

      "/mnt/Videos" = {
        device = "100.107.75.195:/mnt/user/Videos";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "async"
          "rw"
          "intr"
          "hard"
          "noauto"
        ];
      };

      "/mnt/Music" = {
        device = "100.107.75.195:/mnt/user/Music";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "async"
          "rw"
          "intr"
          "hard"
          "noauto"
        ];
      };

      "/mnt/ROMs" = {
        device = "100.107.75.195:/mnt/user/ROMs";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "async"
          "rw"
          "intr"
          "hard"
          "noauto"
        ];
      };

      "/mnt/downloadtemp" = {
        device = "100.107.75.195:/mnt/user/downloadtemp";
        fsType = "nfs";
        options = [
          "x-systemd.automount"
          "x-systemd.idle-timeout=1min"
          "rw"
          "intr"
          "hard"
          "vers=4"
          "noauto"
        ];
      };
    };
  };
}
;
}
