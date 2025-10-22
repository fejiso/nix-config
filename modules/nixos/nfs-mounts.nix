{ config, lib, pkgs, ... }:

{
  # Enable NFS client support
  services.rpcbind.enable = true;
  
  # Create mount points
  systemd.tmpfiles.rules = [
    "d /mnt/Series 0755 root root -"
    "d /mnt/Backups 0755 root root -"
    "d /mnt/Videos 0755 root root -"
    "d /mnt/Music 0755 root root -"
  ];

  # NFS and CIFS mounts
  fileSystems = {
    "/mnt/Series" = {
      device = "100.107.6.18:/mnt/user/Series";
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
      device = "100.107.6.18:/mnt/user/Backups";
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
      device = "100.107.6.18:/mnt/user/Videos";
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
      device = "100.107.6.18:/mnt/user/Music";
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
  };
}
