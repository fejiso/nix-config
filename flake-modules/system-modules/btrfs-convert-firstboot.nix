{ ... }: {
  flake.modules.nixos.btrfs-convert-firstboot =
{ config, lib, pkgs, ... }:

{
  options.services.btrfs-convert-firstboot = {
    enable = lib.mkEnableOption "automatic ext4 to btrfs conversion on first boot";

    rootDevice = lib.mkOption {
      type = lib.types.str;
      default = "/dev/disk/by-label/NIXOS_SD";
      description = "Root device to convert";
    };

    subvolume = lib.mkOption {
      type = lib.types.str;
      default = "@";
      description = "Btrfs subvolume name to create";
    };
  };

  config = lib.mkIf config.services.btrfs-convert-firstboot.enable {
    # Userspace oneshot: detect ext4 root, drop flag, reboot into initrd conversion.
    systemd.services.btrfs-convert-firstboot = {
      description = "Convert root filesystem from ext4 to btrfs on first boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      unitConfig = {
        ConditionPathExists = "!/var/lib/btrfs-convert-firstboot.done";
      };

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = ''
        set -e

        echo "Checking if btrfs conversion is needed..."

        ROOT_FS=$(${pkgs.util-linux}/bin/findmnt -n -o FSTYPE /)
        if [ "$ROOT_FS" = "btrfs" ]; then
          echo "Root is already btrfs, skipping conversion"
          touch /var/lib/btrfs-convert-firstboot.done
          exit 0
        fi

        if [ "$ROOT_FS" != "ext4" ]; then
          echo "Root filesystem is $ROOT_FS, not ext4. Cannot convert."
          touch /var/lib/btrfs-convert-firstboot.done
          exit 1
        fi

        echo "Root is ext4, preparing for btrfs conversion..."

        mkdir -p /boot
        cat > /boot/convert-to-btrfs.flag <<EOF
DEVICE=${config.services.btrfs-convert-firstboot.rootDevice}
SUBVOL=${config.services.btrfs-convert-firstboot.subvolume}
EOF

        touch /var/lib/btrfs-convert-firstboot.done

        echo "Conversion will occur on next boot. Rebooting in 5 seconds..."
        ${pkgs.coreutils}/bin/sleep 5
        ${pkgs.systemd}/bin/systemctl reboot
      '';
    };

    # Initrd side (systemd stage 1).
    boot.initrd.kernelModules = [ "btrfs" "vfat" ];
    boot.initrd.availableKernelModules = [ "btrfs" "vfat" ];

    # Make btrfs/e2fsprogs available in the systemd-initrd PATH.
    boot.initrd.systemd.initrdBin = [ pkgs.btrfs-progs pkgs.e2fsprogs ];

    # Mount unit for /boot inside initrd so we can read the flag file before
    # the root filesystem is touched.
    boot.initrd.systemd.mounts = [
      {
        what = "/dev/disk/by-label/NIXOS_BOOT";
        where = "/boot";
        type = "vfat";
        options = "ro";
        unitConfig.DefaultDependencies = false;
        wantedBy = [ "initrd-root-device.target" ];
        before = [ "btrfs-convert-firstboot.service" ];
      }
    ];

    boot.initrd.systemd.services.btrfs-convert-firstboot = {
      description = "Convert root filesystem from ext4 to btrfs";
      wantedBy = [ "initrd-root-fs.target" ];
      after = [ "initrd-root-device.target" "boot.mount" ];
      before = [ "sysroot.mount" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if [ ! -f /boot/convert-to-btrfs.flag ]; then
          exit 0
        fi

        echo "============================================"
        echo "Converting root filesystem from ext4 to btrfs"
        echo "============================================"

        . /boot/convert-to-btrfs.flag

        echo "Waiting for device $DEVICE..."
        for i in $(seq 1 30); do
          if [ -e "$DEVICE" ]; then break; fi
          sleep 1
        done

        if [ ! -e "$DEVICE" ]; then
          echo "ERROR: Device $DEVICE not found!"
          exit 1
        fi

        echo "Running fsck on ext4..."
        e2fsck -fy "$DEVICE" || true

        echo "Converting to btrfs..."
        btrfs-convert -L "$DEVICE"

        echo "Mounting btrfs filesystem..."
        mkdir -p /mnt/root-convert
        mount -t btrfs "$DEVICE" /mnt/root-convert

        echo "Creating subvolume $SUBVOL..."
        if [ ! -d "/mnt/root-convert/$SUBVOL" ]; then
          btrfs subvolume create "/mnt/root-convert/$SUBVOL"

          shopt -s dotglob
          for item in /mnt/root-convert/*; do
            basename=$(basename "$item")
            if [ "$basename" != "$SUBVOL" ] && [ "$basename" != "ext2_saved" ]; then
              mv "$item" "/mnt/root-convert/$SUBVOL/"
            fi
          done
        fi

        subvol_id=$(btrfs subvolume list /mnt/root-convert | grep "$SUBVOL" | awk '{print $2}')
        if [ -n "$subvol_id" ]; then
          btrfs subvolume set-default "$subvol_id" /mnt/root-convert
        fi

        umount /mnt/root-convert

        mount -o remount,rw /boot
        rm /boot/convert-to-btrfs.flag
        mount -o remount,ro /boot

        echo "Conversion complete! Continuing boot..."
      '';
    };
  };
}
;
}
