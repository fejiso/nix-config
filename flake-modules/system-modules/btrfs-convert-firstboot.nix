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
    # Create systemd service that runs on first boot
    systemd.services.btrfs-convert-firstboot = {
      description = "Convert root filesystem from ext4 to btrfs on first boot";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];

      # Only run once - flag file prevents re-running
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

        # Check if root is already btrfs
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
        echo "This will happen on next boot."

        # Create flag for initrd to do conversion
        mkdir -p /boot
        cat > /boot/convert-to-btrfs.flag <<EOF
DEVICE=${config.services.btrfs-convert-firstboot.rootDevice}
SUBVOL=${config.services.btrfs-convert-firstboot.subvolume}
EOF

        # Mark as done so we don't check again
        touch /var/lib/btrfs-convert-firstboot.done

        echo "Conversion will occur on next boot. Rebooting in 5 seconds..."
        ${pkgs.coreutils}/bin/sleep 5
        ${pkgs.systemd}/bin/systemctl reboot
      '';
    };

    # Add conversion script to initrd
    boot.initrd.postDeviceCommands = lib.mkBefore ''
      if [ -f /boot/convert-to-btrfs.flag ]; then
        echo "============================================"
        echo "Converting root filesystem from ext4 to btrfs"
        echo "============================================"

        # Parse flag file
        . /boot/convert-to-btrfs.flag

        # Wait for device
        echo "Waiting for device $DEVICE..."
        for i in $(seq 1 30); do
          if [ -e "$DEVICE" ]; then
            break
          fi
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

          # Move everything to subvolume (except ext2_saved for rollback)
          echo "Moving files to subvolume..."
          shopt -s dotglob
          for item in /mnt/root-convert/*; do
            basename=$(basename "$item")
            if [ "$basename" != "$SUBVOL" ] && [ "$basename" != "ext2_saved" ]; then
              mv "$item" "/mnt/root-convert/$SUBVOL/"
            fi
          done
        fi

        # Set default subvolume
        subvol_id=$(btrfs subvolume list /mnt/root-convert | grep "$SUBVOL" | awk '{print $2}')
        if [ -n "$subvol_id" ]; then
          btrfs subvolume set-default "$subvol_id" /mnt/root-convert
        fi

        umount /mnt/root-convert

        # Remove flag file
        rm /boot/convert-to-btrfs.flag

        echo "Conversion complete! Continuing boot..."
      fi
    '';

    # Ensure btrfs-progs is available in initrd
    boot.initrd.kernelModules = [ "btrfs" ];
    boot.initrd.availableKernelModules = [ "btrfs" ];

    # Add btrfs tools to initrd
    boot.initrd.extraUtilsCommands = ''
      copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfs
      copy_bin_and_libs ${pkgs.btrfs-progs}/bin/btrfs-convert
      copy_bin_and_libs ${pkgs.e2fsprogs}/bin/e2fsck
    '';
  };
}
;
}
