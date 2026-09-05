{ ... }: {
  flake.modules.nixos.media-storage =
# Media storage on a bcachefs pool mounted at /mnt/user (see
# hosts/butthead/nixos/hardware-configuration.nix), with aggressive VFS
# caching and HDD spindown. Extracted from hosts/butthead/nixos; the disk
# layout (SSD on sdc, HDDs for the pool) is butthead's.
{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.services.media-storage;
in
{
  options.services.media-storage.enable = mkEnableOption "media storage (bcachefs pool at /mnt/user)";

  config = mkIf cfg.enable {
    # Download + SnapRAID working directories
    systemd.tmpfiles.rules = [
      # Download directories with proper permissions
      "d /mnt/user/download 0775 root media-services -"
      "d /mnt/user/downloadtemp 0775 root media-services -"
      "d /mnt/user/downloadtemp/incomplete 0775 root media-services -"
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
      hdparm
    ];
  };
};
}
