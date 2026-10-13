#!/usr/bin/env bash
# Flash NixOS to a Samsung Galaxy S7 (herolte) running in Download mode.
#
#   nix build .#images.herolte -o result-herolte
#   scripts/flash-herolte.sh [result-herolte]
#
# Phone side: power off, hold Volume Down + Home + Power, confirm with
# Volume Up, then plug in USB. Flashes boot.img to BOOT and the ext4 rootfs
# to USERDATA (keeps the stock PIT layout; RECOVERY is untouched, so TWRP
# remains available for rescue). Reboots when done.
set -euo pipefail

img="${1:-result-herolte}"

if [ ! -f "$img/boot.img" ] || [ ! -f "$img/system.img" ]; then
  echo "error: $img does not look like .#images.herolte (need boot.img + system.img)" >&2
  exit 1
fi

if ! heimdall detect >/dev/null 2>&1; then
  echo "error: no device in Download mode detected" >&2
  exit 1
fi

# Sanity-check the PIT labels we rely on (BOOT, USERDATA).
heimdall print-pit --no-reboot 2>/dev/null | grep -q "Partition Name: BOOT" \
  || { echo "error: PIT has no BOOT partition — is this a herolte (SM-G930F)?" >&2; exit 1; }
heimdall print-pit --no-reboot 2>/dev/null | grep -q "Partition Name: USERDATA" \
  || { echo "error: PIT has no USERDATA partition" >&2; exit 1; }

echo "Flashing BOOT <- $img/boot.img"
echo "Flashing USERDATA <- $img/system.img (this takes a while)"
heimdall flash --BOOT "$img/boot.img" --USERDATA "$img/system.img"

echo "Done. Phone will reboot into NixOS."
echo "Next: log in on the display or 'adb shell' (root/herolte), grab the SSH"
echo "host key, add &herolte_ssh/&herolte_age to .sops.yaml, 'sops updatekeys"
echo "secrets/wifi.yaml', then 'colmena apply --on herolte'."
