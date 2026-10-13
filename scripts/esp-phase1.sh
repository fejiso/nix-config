#!/usr/bin/env bash
# Phase 1: Tungsten ESP Migration
# Creates a dedicated 2GB ESP on the Crucial 4TB NVMe SSD (NixOS drive)
# and populates it with existing NixOS boot files.
#
# MUST BE RUN WITH SUDO.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "=== Tungsten ESP Migration: Phase 1 ==="

# Target disk: Crucial 4TB NVMe SSD
DISK_BY_ID="/dev/disk/by-id/nvme-CT4000P3SSD8_2319E6D42CC6"

if [ ! -b "$DISK_BY_ID" ]; then
    echo "ERROR: Target disk $DISK_BY_ID not found!" >&2
    exit 1
fi

REALDEV="$(readlink -f "$DISK_BY_ID")"
echo "Target disk resolved to: $REALDEV ($DISK_BY_ID)"

# Safety checks:
# 1. Verify disk size is ~4TB (CT4000P3SSD8)
DISK_SIZE="$(lsblk -dn -o SIZE "$REALDEV" | tr -d ' ')"
echo "Target disk size: $DISK_SIZE"
case "$DISK_SIZE" in
    3.6T|3.7T|4T|3.64T|3.63T) ;;
    *)
        echo "ERROR: Disk size $DISK_SIZE unexpected for Crucial 4TB! Aborting." >&2
        exit 1
        ;;
esac

# 2. Verify partition 6 has the NixOS LUKS UUID (7f1bd4db-58b3-40aa-be5c-d38ba434cfcb)
# Use blkid on the partition itself -- lsblk also lists the decrypted cryptroot
# child's btrfs UUID, yielding two lines and breaking an exact-match compare.
P6_UUID="$(blkid -s UUID -o value "${REALDEV}p6" 2>/dev/null || true)"
if [ "$P6_UUID" != "7f1bd4db-58b3-40aa-be5c-d38ba434cfcb" ]; then
    echo "ERROR: Safety check failed! ${REALDEV}p6 UUID ($P6_UUID) does not match expected NixOS cryptroot UUID (7f1bd4db-58b3-40aa-be5c-d38ba434cfcb)." >&2
    exit 1
fi
echo "Safety check passed: ${REALDEV}p6 verified as active NixOS cryptroot."

# 3. Verify partition 2 is currently mounted as /boot
BOOT_DEV="$(findmnt -n -o SOURCE /boot || true)"
if [ "$BOOT_DEV" != "${REALDEV}p2" ]; then
    echo "ERROR: Expected ${REALDEV}p2 to be mounted at /boot, but found '$BOOT_DEV'." >&2
    exit 1
fi
echo "Safety check passed: ${REALDEV}p2 is currently mounted at /boot."

# Step 1: Backup current partition table
BACKUP_FILE="/root/crucial-partition-table-$(date +%Y%m%d_%H%M%S).dump"
echo ""
echo "Creating backup of partition table to $BACKUP_FILE ..."
sfdisk -d "$REALDEV" > "$BACKUP_FILE"
echo "Backup saved."

# Step 2: Delete old Windows leftover partitions (1, 3, 4, 5)
# sfdisk checks whether the disk is in use via the BLKRRPART ioctl, which
# fails with EBUSY because p2 (/boot) is mounted and p6 is held by cryptroot.
# --no-reread skips that check, --no-tell-kernel skips the (doomed) whole-disk
# re-read; we inform the kernel per-partition with partx (BLKPG ioctls) instead.
echo ""
echo "Deleting old Windows leftover partitions (1, 3, 4, 5)..."
sfdisk --no-reread --no-tell-kernel --delete "$REALDEV" 1 3 4 5

# Verify the delete landed in the ON-DISK partition table. Checking /dev nodes
# would be useless here: partx -d below removes them from the kernel's view
# whether or not the delete actually succeeded, and a stale p1 would then get
# EDITED IN PLACE by 'sfdisk -N 1' instead of freshly created.
if sfdisk -d "$REALDEV" | grep -qE "^${REALDEV}p[1345] :"; then
    echo "ERROR: partitions 1/3/4/5 still present in on-disk table! Aborting." >&2
    exit 1
fi
echo "Old partitions confirmed deleted from partition table."

# Drop the deleted partitions from the kernel's view
partx -d --nr 3-5 "$REALDEV" 2>/dev/null || true
partx -d --nr 1 "$REALDEV" 2>/dev/null || true
udevadm settle
sleep 1

# Step 3: Create new 2GB ESP partition in slot 1
# Start sector: 1128448 (1 MiB aligned, immediately after p2 which ends at 1128447)
# Size: 4194304 sectors = 2 GiB
# Type: c12a7328-f81f-11d2-ba4b-00a0c93ec93b (EFI System)
echo ""
echo "Creating new 2GB ESP in partition slot 1 (sectors 1128448 - 5322751)..."
echo 'start=1128448, size=4194304, type=c12a7328-f81f-11d2-ba4b-00a0c93ec93b, name="NIXOS-ESP"' | sfdisk --no-reread --no-tell-kernel -N 1 "$REALDEV"

# Step 4: Tell kernel about the new partition (per-partition ioctl; a whole-disk
# re-read would fail while p2/p6 are in use)
echo ""
echo "Updating kernel partition table..."
partx -a --nr 1 "$REALDEV"
udevadm settle
sleep 1

NEW_PART="${REALDEV}p1"
if [ ! -b "$NEW_PART" ]; then
    echo "ERROR: New partition $NEW_PART block device does not exist!" >&2
    exit 1
fi

# Sanity-check the kernel learned the partition at exactly the intended start
# sector before we format it.
REAL_START="$(cat "/sys/class/block/$(basename "$REALDEV")p1/start" 2>/dev/null || echo missing)"
if [ "$REAL_START" != "1128448" ]; then
    echo "ERROR: $NEW_PART starts at sector $REAL_START, expected 1128448! Aborting before mkfs." >&2
    exit 1
fi

# Step 5: Format new ESP with FAT32
echo ""
echo "Formatting $NEW_PART with FAT32 (label: NIXOS-ESP)..."
mkfs.vfat -F 32 -n NIXOS-ESP "$NEW_PART"
udevadm settle

NEW_UUID="$(blkid -s UUID -o value "$NEW_PART")"
if [ -z "$NEW_UUID" ]; then
    echo "ERROR: Failed to retrieve UUID for $NEW_PART!" >&2
    exit 1
fi
echo "New ESP formatted successfully. UUID: $NEW_UUID"
echo "$NEW_UUID" > /tmp/new-esp-uuid
chmod 644 /tmp/new-esp-uuid

# Step 6: Mount and copy boot files
echo ""
echo "Mounting $NEW_PART at /mnt/newesp..."
mkdir -p /mnt/newesp
mount "$NEW_PART" /mnt/newesp

echo "Copying NixOS boot files from /boot to /mnt/newesp..."
mkdir -p /mnt/newesp/EFI
[ -d /boot/EFI/systemd ] && cp -a /boot/EFI/systemd /mnt/newesp/EFI/
[ -d /boot/EFI/BOOT ]    && cp -a /boot/EFI/BOOT    /mnt/newesp/EFI/
[ -d /boot/EFI/nixos ]   && cp -a /boot/EFI/nixos   /mnt/newesp/EFI/
[ -d /boot/EFI/Linux ]   && cp -a /boot/EFI/Linux   /mnt/newesp/EFI/
[ -d /boot/loader ]      && cp -a /boot/loader      /mnt/newesp/

sync

echo ""
echo "=== Phase 1 Verification ==="
echo "Files copied to new ESP:"
ls -la /mnt/newesp
ls -la /mnt/newesp/EFI
[ -d /mnt/newesp/loader ] && ls -la /mnt/newesp/loader

echo ""
echo "Unmounting /mnt/newesp..."
umount /mnt/newesp

echo ""
echo "=========================================================="
echo " PHASE 1 SUCCESSFUL!"
echo " New ESP UUID: $NEW_UUID (saved to /tmp/new-esp-uuid)"
echo " Ready for NixOS configuration updates."
echo "=========================================================="
