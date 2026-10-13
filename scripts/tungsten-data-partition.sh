#!/usr/bin/env bash
# tungsten-data-partition.sh — create LUKS-encrypted /data in the ~197.5G free
# region on the Crucial 4TB (sectors 5322752..416532479, between p1 ESP and p6).
#
# Run:  sudo bash scripts/tungsten-data-partition.sh
# Safe: only touches the FREE region; p1/p6 are never written to.
set -euo pipefail

DISK=/dev/disk/by-id/nvme-CT4000P3SSD8_2319E6D42CC6
START=5322752
END=416532479   # last sector before p6 (starts at 416532480)
SIZE=$((END - START + 1))
GPT_LINUX_FS=0FC63DAF-8483-4772-8E79-3D69D8477DE4
LABEL=data
MAPPER=cryptdata
KEYDIR=/root/keys
KEYFILE=$KEYDIR/cryptdata.key

[[ $EUID -eq 0 ]] || { echo "run as root"; exit 1; }

echo "=== current table ==="
fdisk -l "$DISK"

# sanity: p6 must start exactly at 416532480
p6start=$(cat "/sys/class/block/$(basename "$(readlink -f "$DISK")")p6/start")
[[ "$p6start" == "416532480" ]] || { echo "ABORT: p6 first sector is $p6start, expected 416532480"; exit 1; }

EXISTING=$(lsblk -lnpo NAME "$DISK" | while read -r p; do
  s=$(cat "/sys/class/block/${p##*/}/start" 2>/dev/null || echo 0)
  if [[ "$s" == "$START" ]]; then echo "$p"; fi
done)
if [[ -n "$EXISTING" ]]; then
  echo "=== partition already exists ($EXISTING), skipping creation ==="
else
  echo "=== creating partition in free region $START..$END (size $SIZE sectors) ==="
  echo "start=$START, size=$SIZE, type=$GPT_LINUX_FS, name=\"luks-data\"" | sfdisk -a --no-reread "$DISK"
  partx -a "$DISK" || true   # tell kernel about the new partition (full reread would fail: disk busy)
  sleep 2
fi

NEW_PART=$(lsblk -lnpo NAME "$DISK" | while read -r p; do
  s=$(cat "/sys/class/block/${p##*/}/start" 2>/dev/null || echo 0)
  if [[ "$s" == "$START" ]]; then echo "$p"; fi
done)
[[ -n "$NEW_PART" ]] || { echo "ABORT: could not find new partition"; exit 1; }
[[ "$(blkid -s TYPE -o value "$NEW_PART" 2>/dev/null || true)" == "" ]] || { echo "ABORT: $NEW_PART already formatted"; exit 1; }
echo "new partition: $NEW_PART"

echo "=== luksFormat (you will be asked for a passphrase — suggest reusing the cryptroot one) ==="
cryptsetup luksFormat --type luks2 "$NEW_PART"

echo "=== opening + mkfs.btrfs ==="
cryptsetup open "$NEW_PART" "$MAPPER"
mkfs.btrfs -f -L "$LABEL" "/dev/mapper/$MAPPER"

echo "=== keyfile on encrypted root for auto-unlock ==="
mkdir -p "$KEYDIR"
chmod 700 "$KEYDIR"
dd if=/dev/urandom of="$KEYFILE" bs=512 count=4 status=none
chmod 400 "$KEYFILE"
cryptsetup luksAddKey "$NEW_PART" "$KEYFILE"

mkdir -p /data
mount -o compress=zstd "/dev/mapper/$MAPPER" /data

echo
echo "=== DONE — give these to the config ==="
echo "LUKS UUID : $(cryptsetup luksUUID "$NEW_PART")"
echo "btrfs UUID: $(blkid -s UUID -o value "/dev/mapper/$MAPPER")"
df -h /data
