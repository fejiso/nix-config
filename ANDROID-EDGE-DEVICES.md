# Android phones & tablets as edge servers

Repurposing old Android devices as headless NixOS edge servers / telemetry
stations, via [Mobile NixOS](https://mobile-nixos.org/) (a non-flake flake
input; its module set is imported by each host and applies its own overlay)
plus in-repo device ports under `devices/<vendor>-<codename>/`. All port
facts (kernel source, boot offsets, firmware) are mirrored from postmarketOS
pmaports, with kernel configs and patches vendored in-tree.

Rootfs is a plain ext4 image flashed to the userdata partition (stage-1 finds
it by filesystem label); the boot partition holds an Android `boot.img`
(kernel + mobile-nixos stage-1 initrd + DTB). Every host is **cross-compiled
from x86** (`nixpkgs.hostPlatform`/`buildPlatform`, `embedded.crossSafe`) —
no aarch64/armv7l builder required; results land on the netbird `nix-serve`
caches.

## Device matrix

| Host | Device | Arch | Kernel | Boot chain | WiFi |
|---|---|---|---|---|---|
| `herolte` | Samsung Galaxy S7 (SM-G930F/FD) | aarch64 | downstream 3.18 (8890q) | heimdall → `BOOT` | BCM4359 (dhd, blobs packaged in `devices/samsung-herolte/firmware`) |
| `hammerhead` | LG Nexus 5 | armv7l | mainline 6.11 (msm8974-mainline) | fastboot → `boot` | BCM4339 (brcmfmac; NVRAM vendored, `.bin` from linux-firmware) |
| `tissot` | Xiaomi Mi A1 | aarch64 | mainline 6.11 (msm8953-mainline) | lk2nd → fastboot | WCN3680 (blobs extracted from the stock modem partition at boot) |
| `thor` | Kindle Fire HDX 7 | armv7l | downstream 3.4 | **WIP** — aboot exploit (Fire OS 13.3.2.4 downgrade); kernel has no WLAN driver at all |
| `ford` | Kindle Fire 7 (2015) | armv7l | downstream 3.10 (ATAGS, no DT) | **WIP** — amonet bootrom exploit; consys blobs unsourced |
| `austin` | Kindle Fire 7 (2017) | armv7l | downstream 3.10 (ATAGS, no DT) | **WIP** — amonet bootrom exploit; consys blobs unsourced |
| `mustang` | Kindle Fire 7 (2019) | armv7l | downstream 4.9 (zImage-dtb) | **WIP** — kamakiri bootrom exploit; consys blobs unsourced |

"Kindle Fire 7" is three different devices (ford/austin/mustang by year).
None of the Kindles is usable as a WiFi server today: no redistributable
firmware exists in pmaports (blobs must be harvested from the stock OS), and
every one needs a bootloader exploit before anything can be flashed. The
ports are evaluation-complete skeletons — finishing them is a
firmware-sourcing project. `herolte`/`hammerhead`/`tissot` are the practical
fleet.

## Building & flashing

```bash
nix build .#images.herolte -o result-herolte
scripts/flash-herolte.sh result-herolte      # heimdall (Download mode)

nix build .#images.hammerhead -o result-hammerhead
scripts/flash-fastboot.sh result-hammerhead  # fastboot
# tissot: flash lk2nd to `boot` once, then flash-fastboot.sh from inside lk2nd
```

Each image output is mobile-nixos' `android-fastboot-images`: `boot.img`,
`system.img` (the ext4 rootfs), and a reference `flash-critical.sh`.

## First boot / secrets chicken-and-egg

WiFi uses the shared iwd + sops `wifi-secrets` stack
(`flake-modules/system/networking.nix`). The phone's SSH host key isn't in
`.sops.yaml` until it has booted once:

1. Flash, boot, log in on the display (root/`<hostname>`) or `adb shell`
   (herolte enables adbd).
2. Grab the host key (`ssh-keyscan localhost`), add `&<host>_ssh` /
   `&<host>_age` anchors to `.sops.yaml`, and append them to the generic
   `secrets/.*$` creation rule (placeholders are commented there).
3. `sops updatekeys secrets/wifi.yaml`, then `colmena apply --on <host>`.

## Updates

Colmena over netbird, like the SBCs. `herolte` and `hammerhead` have a
hash-guarded `boot.loader.external` activation hook that rewrites the boot
partition when the boot image actually changes. `tissot` and the Kindles
only print a reminder — lk2nd owns tissot's boot partition layout, and the
Kindle boot chains are too fragile to self-update; reflash via fastboot.

## Debugging

- No UART on any of these without hardware mods: the console is the display
  (`console=tty1`), plus `adb shell` on herolte.
- mobile-nixos stage-1 gives a boot menu/splash and (on the mainline-kernel
  devices) USB RNDIS networking for bench debugging.
- `thor` QCDT note: pmOS builds its dt.img with `dtbTool --version=1`;
  mobile-nixos' kernel-builder doesn't pass that flag (fix at bring-up).
