#!/usr/bin/env bash
# Phase 2: Tungsten ESP Migration
# Mounts the new ESP at /boot, runs nixos-rebuild switch to install systemd-boot
# and register the new EFI boot entry, and verifies bootctl and efibootmgr.
#
# MUST BE RUN WITH SUDO.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: This script must be run as root (use sudo)." >&2
    exit 1
fi

echo "=== Tungsten ESP Migration: Phase 2 ==="

UUID_FILE="/tmp/new-esp-uuid"
if [ -n "${1:-}" ]; then
    NEW_UUID="$1"
elif [ -f "$UUID_FILE" ]; then
    NEW_UUID="$(cat "$UUID_FILE" | tr -d ' \n\r')"
else
    echo "ERROR: No UUID provided and $UUID_FILE not found." >&2
    echo "Usage: sudo $0 [NEW_ESP_UUID]" >&2
    exit 1
fi

NEW_DEV="/dev/disk/by-uuid/$NEW_UUID"
if [ ! -b "$NEW_DEV" ]; then
    echo "ERROR: Block device for UUID $NEW_UUID ($NEW_DEV) not found!" >&2
    exit 1
fi

echo "Target new ESP: $NEW_DEV (UUID: $NEW_UUID)"

# Guard: the nixos-rebuild below must install to the NEW esp. If the config
# still references the old /boot UUID (E02A-0157), fstab would point at the
# old 100M partition after reboot while systemd-boot lands on the new one.
HWCFG="/home/z-247/Syncthing/dev/nix-config/hosts/tungsten/nixos/hardware-configuration.nix"
if ! grep -q "$NEW_UUID" "$HWCFG"; then
    echo "ERROR: $HWCFG does not reference new UUID $NEW_UUID yet." >&2
    echo "Update the fileSystems.\"/boot\" entry BEFORE running Phase 2." >&2
    exit 1
fi
if grep -q "E02A-0157" "$HWCFG"; then
    echo "ERROR: $HWCFG still contains old ESP UUID E02A-0157." >&2
    exit 1
fi

# Step 1: Unmount old /boot and mount new ESP
# Fail hard if /boot is busy: mounting the new ESP on top of the old one
# would create a split-brain state that's painful to debug.
echo ""
echo "Unmounting old /boot..."
umount /boot

echo "Mounting new ESP at /boot..."
mount -o fmask=0077,dmask=0077 "$NEW_DEV" /boot

# Step 2: Run nixos-rebuild switch
echo ""
echo "Rebuilding and switching NixOS configuration on tungsten..."
# --install-bootloader (NIXOS_INSTALL_BOOTLOADER=1) forces a full 'bootctl
# install'. Without it, the builder sees the EFI/systemd binaries we copied in
# Phase 1 and only runs 'bootctl update', which NEVER creates the EFI firmware
# boot entry -- Boot0002 would keep pointing at the old p2, and Phase 3 would
# leave the system unbootable. canTouchEfiVariables=true so the entry lands.
nixos-rebuild switch --install-bootloader --flake /home/z-247/Syncthing/dev/nix-config#tungsten

# Step 3: Verification
echo ""
echo "=== Phase 2 Verification ==="
echo "Disk space on /boot:"
df -h /boot

echo ""
echo "Bootctl status:"
bootctl status || true

echo ""
echo "EFI Boot Manager entries:"
EFIBOOTMGR="$(which efibootmgr 2>/dev/null || ls -d /nix/store/*-efibootmgr-*/bin/efibootmgr 2>/dev/null | head -n 1 || true)"
if [ -n "$EFIBOOTMGR" ] && [ -x "$EFIBOOTMGR" ]; then
    "$EFIBOOTMGR" -v
else
    echo "efibootmgr binary not in PATH or store"
fi

echo ""
echo "=========================================================="
echo " PHASE 2 SUCCESSFUL!"
echo " NixOS has been rebuilt with the new 2GB ESP."
echo " You may now reboot and verify NixOS & Windows boot correctly."
echo "=========================================================="
