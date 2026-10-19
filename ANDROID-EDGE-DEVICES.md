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

All images: `nix build .#images.<host> -o result-<host>` — each output is
mobile-nixos' `android-fastboot-images` containing `boot.img`, `system.img`
(the ext4 rootfs), and a reference `flash-critical.sh`. Flashing `userdata`
**wipes the stock OS** — back up first if you care.

### herolte (Galaxy S7) — heimdall

Prereq: enable *Developer options → OEM unlock* in stock Android first
(Exynos models need no unlock code).

```bash
nix build .#images.herolte -o result-herolte
scripts/flash-herolte.sh result-herolte
```

Phone side: power off → hold Volume Down + Home + Power → Volume Up to
confirm Download mode → plug in USB. The script verifies the PIT (BOOT +
USERDATA) before flashing. RECOVERY is untouched — install TWRP there
beforehand if you want a rescue OS.

### hammerhead (Nexus 5) — fastboot

Prereq: unlock the bootloader: boot into fastboot (power off → Volume Down +
Power), `fastboot oem unlock` (this wipes the device).

```bash
nix build .#images.hammerhead -o result-hammerhead
scripts/flash-fastboot.sh result-hammerhead   # flashes boot + userdata
fastboot reboot
```

### tissot (Mi A1) — lk2nd + fastboot

tissot's stock bootloader can't boot a mainline boot.img directly; lk2nd (a
secondary bootloader living in the `boot` partition) sits in between. One-time
setup, then normal fastboot flashing via lk2nd.

```bash
# 0. Prereq: unlock the bootloader (fastboot mode: power off, Vol Down +
#    Power):  fastboot oem unlock

# 1. Build and flash lk2nd (once per device):
nix build .#lk2nd-msm8953
fastboot flash boot result/lk2nd.img

# 2. Boot into lk2nd (it shows a splash and exposes fastboot itself; hold
#    Volume Down while booting to force its fastboot mode), then flash NixOS:
nix build .#images.tissot -o result-tissot
scripts/flash-fastboot.sh result-tissot
fastboot reboot
```

lk2nd keeps the real boot image at an offset *inside* the boot partition —
which is why tissot has no on-device boot.img self-update hook; kernel/stage-1
changes are reflashed through lk2nd's fastboot (step 2).

### Kindles (thor / ford / austin / mustang) — WIP, exploit first

No official unlock exists for any of these; nothing can be flashed until the
bootrom/aboot exploit has been applied and fastboot is available:

- `thor` (HDX 7): HDX aboot exploit — downgrade to Fire OS 13.3.2.4 first
- `ford` / `austin` (Fire 7 2015/2017): [amonet](https://github.com/amonet-kamakiri/amonet) (MT8127)
- `mustang` (Fire 7 2019): kamakiri (MT8163)

After the exploit, flashing is `scripts/flash-fastboot.sh result-<host>`.
Remember these ports are skeletons without working WiFi — see the matrix
above before investing the exploit effort.

## First boot / secrets chicken-and-egg

WiFi uses the shared iwd + sops `wifi-secrets` stack
(`flake-modules/system/networking.nix`). The phone's SSH host key isn't in
the private repo's `.sops.yaml` until it has booted once:

1. Flash, boot, log in on the display (root/`<hostname>`) or `adb shell`
   (herolte enables adbd).
2. Grab the host key (`ssh-keyscan localhost`), add `&<host>_ssh` /
   `&<host>_age` anchors to `.sops.yaml` **in `~/dev/nix-config-private`**, and
   append them to the generic `secrets/.*$` creation rule (placeholders are
   commented there).
3. `sops updatekeys secrets/wifi.yaml` (in the private repo), push, then
   `nix flake update private` here, then `colmena apply --on <host>`.

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
