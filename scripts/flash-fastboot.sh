#!/usr/bin/env bash
# Flash a Mobile NixOS fastboot image to an Android phone/tablet.
#
#   nix build .#images.hammerhead -o result-hammerhead
#   scripts/flash-fastboot.sh [result-hammerhead]
#
# Device must be in fastboot mode (for tissot: inside lk2nd, see
# scripts/README notes or the host docs). Flashes boot.img to `boot` and the
# ext4 rootfs to `userdata`. This WIPES userdata — the stock OS is replaced.
set -euo pipefail

img="${1:-result}"

if [ ! -f "$img/boot.img" ] || [ ! -f "$img/system.img" ]; then
  echo "error: $img does not look like a mobile-nixos fastboot image set" >&2
  exit 1
fi

fastboot getvar product 2>/dev/null || {
  echo "error: no fastboot device detected" >&2
  exit 1
}

echo "Flashing boot <- $img/boot.img"
fastboot flash boot "$img/boot.img"
echo "Flashing userdata <- $img/system.img (this takes a while)"
fastboot flash userdata "$img/system.img"

echo "Done. Reboot with: fastboot reboot"
echo "Next: log in on the display (root / <hostname>), grab the SSH host key,"
echo "add it to .sops.yaml, 'sops updatekeys secrets/wifi.yaml', then"
echo "'colmena apply --on <hostname>'."
