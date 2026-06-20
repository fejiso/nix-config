# Multi-Platform Nix Configuration

This repository contains a comprehensive Nix configuration for managing multiple
systems across different platforms:

- NixOS (Linux) — x86_64 and ARM64 (aarch64)
- macOS (via nix-darwin)
- Non-NixOS Linux systems (via standalone home-manager, e.g. Ubuntu)
- ARM single-board computers with SD card image generation

The flake follows the **dendritic** pattern: it is built with
[flake-parts](https://github.com/hercules-ci/flake-parts) and
[import-tree](https://github.com/vic/import-tree), so every file under
`flake-modules/` is automatically imported as a flake-parts module. There is no
central wiring file — modules contribute to shared option trees and hosts compose
them. See [Repository Structure](#repository-structure) below.

## What this provides

This flake-based configuration supports:

- **x86_64 NixOS systems**: `elitedex`, `lenovix`, `hispanas`, `a8`, `blacktop`,
  `hierro`, `butthead`, `snuffles`
- **ARM NixOS systems**: `rpi3` (Raspberry Pi 3), `pine64` (Pine64 SBC),
  `xpi-s905x3` (Amlogic S905X3 TV box) — all aarch64 — plus `z-turn`
  (MYIR Z-turn, Xilinx Zynq-7020 FPGA SoC, **armv7l**, cross-compiled with the
  `linux-xlnx` / `u-boot-xlnx` forks)
- **macOS system**: `work-laptop` (aarch64-darwin, via nix-darwin)
- **Standalone home-manager configurations** (non-NixOS Linux):
  `superfer@devdesktop` (x86_64 Ubuntu) and `ubuntu@amp1` (aarch64 Ubuntu,
  also used as a native ARM remote builder)
- **SD card image generation**: Bootable **btrfs** images for ARM single-board
  computers (`rpi3`, `pine64`, `xpi-s905x3`, `z-turn`)
- **Cross-platform support**: aarch64/x86_64 on both Linux and Darwin

## Channels & toolchain

- **nixpkgs**: `nixos-26.05` (stable), with `nixpkgs-unstable` and
  `nixpkgs-master` available as additional inputs for selective pinning
- **home-manager**: `release-26.05`
- **Deployment**: [Colmena](https://github.com/zhaofengli/colmena) for NixOS
  hosts and [deploy-rs](https://github.com/serokell/deploy-rs) for
  home-manager activations on foreign distros
- **Containers**: rootless Podman managed declaratively with
  [quadlet-nix](https://github.com/SEIAROTg/quadlet-nix)
- **Secrets**: [sops-nix](https://github.com/Mic92/sops-nix)

# Repository Structure

The configuration is organized as follows:

- **`flake.nix`**: Minimal entrypoint — declares inputs and hands the whole
  `flake-modules/` tree to flake-parts via `import-tree`.

- **`flake-modules/`**: Every `.nix` file here is a flake-parts module, imported
  automatically. Organized into:
  - **`hosts/`**: One file per machine. Each host *composes* feature modules
    (`config.flake.modules.nixos.<name>` / `…homeManager.<name>`) and registers
    its `nixosConfigurations` / `darwinConfigurations` / `homeConfigurations`,
    plus its Colmena node and (for ARM) its SD image output.
  - **`system/`**: Foundation NixOS modules merged into the
    `flake.modules.nixos.default` that every host imports (nix settings,
    networking, netbird, users, security, sops, services, podman, seedlink,
    socks-proxy, distributed builds, …).
  - **`system-modules/`**: Opt-in NixOS feature modules
    (`flake.modules.nixos.<name>`) — desktop, laptop, development, emulation,
    media, downloads, tdarr, adsb, quadlet-containers, novasdr, openclaw,
    backup, storage-box mount, network-watchdog, embedded, etc.
  - **`home/`**: Foundation home-manager modules merged into
    `flake.modules.homeManager.default` (base, shell, terminal, tools, git, …).
  - **`home-modules/`**: Opt-in home-manager feature modules (niri, sway, fish,
    zsh, wezterm, zellij, git, mpd, beets, tidalcycles, gpg, kanshi,
    atuin-server, dev-heavy, …).
  - **`options.nix`**: Declares the `flake.modules.{nixos,homeManager}` option
    trees that the dendritic pattern accumulates into.
  - **`colmena.nix`** / **`deploy.nix`**: Deployment outputs (Colmena hive and
    deploy-rs nodes).
  - **`sd-images.nix`**, **`overlays.nix`**, **`formatter.nix`**, **`meta.nix`**:
    SD image / overlay / formatter / target-systems plumbing.

- **`hosts/<name>/`**: Per-host *machine-specific* files (hardware
  configuration, host-only tweaks, `home/`, and for ARM hosts `nixos/sd-image.nix`).
  These are imported by the matching `flake-modules/hosts/<name>.nix`.

- **`modules/darwin/`**: Placeholder for custom Darwin modules (currently
  empty; the macOS host is configured in `hosts/work-laptop/darwin/`).

- **`overlays/`**: Custom package overlays (exposed via `flake-modules/overlays.nix`).

- **`secrets/`**: Encrypted secrets managed by sops-nix.

## How a host is composed

Each host file picks a base plus opt-in features. For example, `butthead`
(the media/server hub):

```nix
# flake-modules/hosts/butthead.nix
import ../../lib/mk-host.nix {
  inherit inputs config;
  name = "butthead";
  modules = [                                  # opt-in features on top of `default`
    config.flake.modules.nixos.desktop
    config.flake.modules.nixos.media-services
    config.flake.modules.nixos.download-services
    config.flake.modules.nixos.quadlet-containers
    config.flake.modules.nixos.tdarr-worker
    # …
  ];
  homeModules = [                              # home-manager opt-ins for user z-247
    config.flake.modules.homeManager.development
    config.flake.modules.homeManager.desktop
  ];
}
```

`lib/mk-host.nix` expands this into matching `nixosConfigurations.butthead`
(for `nixos-rebuild`) and `colmenaNodes.butthead` (for remote deployment) from
the same module list, appending `hosts/butthead/nixos` (machine-specific files)
automatically. ARM hosts pass `sdImage = true` to also get `images.<name>`.

### Host roles at a glance

| Host         | Platform        | Type            | Role |
|--------------|-----------------|-----------------|------|
| `elitedex`   | x86_64-linux    | NixOS           | Desktop + emulation |
| `lenovix`    | x86_64-linux    | NixOS           | Minimal laptop |
| `blacktop`   | x86_64-linux    | NixOS           | Desktop/laptop, development, tdarr worker, ADS-B |
| `butthead`   | x86_64-linux    | NixOS           | Media/download/container hub (quadlet, nspawn, tdarr) |
| `hierro`     | x86_64-linux    | NixOS           | Build host, development, OpenClaw |
| `hispanas`   | x86_64-linux    | NixOS           | SDR (NovaSDR), desktop, development |
| `snuffles`   | x86_64-linux    | NixOS           | ADS-B receiver + feeders, network-watchdog |
| `a8`         | x86_64-linux    | NixOS           | Minimal base host |
| `rpi3`       | aarch64-linux   | NixOS + SD img  | Raspberry Pi 3, embedded |
| `pine64`     | aarch64-linux   | NixOS + SD img  | Pine64 SBC, embedded |
| `xpi-s905x3` | aarch64-linux   | NixOS + SD img  | Amlogic S905X3 box, embedded |
| `z-turn`     | armv7l-linux    | NixOS + SD img  | MYIR Z-turn (Zynq-7020 FPGA SoC); linux-xlnx/u-boot-xlnx, cross-compiled |
| `work-laptop`| aarch64-darwin  | nix-darwin      | macOS work machine |
| `devdesktop` | x86_64-linux    | home-manager    | Standalone HM on Ubuntu (`superfer@devdesktop`) |
| `amp1`       | aarch64-linux   | home-manager    | Standalone HM on Ubuntu + native ARM builder (`ubuntu@amp1`) |

## Key Features

1. **Dendritic flake-parts layout**: modules self-register into shared option
   trees; hosts compose features à la carte — no monolithic `flake.nix`.
2. **Multi-platform support**: NixOS (x86_64 & ARM64), macOS (nix-darwin), and
   non-NixOS Linux (standalone home-manager).
3. **ARM/Embedded support**: SD card image generation for aarch64 boards
   (Raspberry Pi 3, Pine64, Amlogic S905X3) and the armv7l Xilinx Zynq-7020
   (MYIR Z-turn, via the `linux-xlnx`/`u-boot-xlnx` forks, cross-compiled from
   x86). All build a **btrfs** root directly, grown to fill the card on first
   boot — generic, shared via `flake-modules/system-modules/sd-image-btrfs.nix`.
4. **Dual deployment**: Colmena for NixOS hosts, deploy-rs for home-manager on
   foreign distros (e.g. `amp1`).
5. **Distributed builds**: x86_64 builders plus `amp1` as a native aarch64
   remote builder, with a `nix-serve` binary cache.
6. **Rootless containers**: declarative Podman via quadlet-nix — media stack
   (Sonarr/Radarr/Lidarr/Prowlarr/Emby/qBittorrent/SABnzbd/Gluetun, …) and
   utility containers, plus systemd-nspawn where needed.
7. **Secrets management**: sops-nix for netbird keys, VPN/API credentials,
   backup passwords, Pushover tokens, etc.
8. **Netbird mesh VPN**: all hosts join the mesh (`wt0` interface); several
   services are firewalled to mesh-only.
9. **Backups**: Kopia-based snapshot backups (migrated from Borg) and a Hetzner
   Storage Box CIFS mount.
10. **Specialized services**: ADS-B flight tracking (readsb + feeders), SDR
    (NovaSDR), SeedLink seismic-data relays, Tdarr transcoding, OpenClaw,
    TGTG watcher.
11. **Desktop**: Niri Wayland compositor (Sway also available), with the full
    home-manager environment (fish/zsh, wezterm, zellij/tmux, git+GPG, atuin, …).
12. **Hardware support**: nixos-hardware profiles (including Raspberry Pi 3).

## Usage

### NixOS Systems

```bash
# Apply configuration (replace hostname with your system name)
sudo nixos-rebuild switch --flake .#hostname

# Examples - x86_64 hosts:
sudo nixos-rebuild switch --flake .#butthead
sudo nixos-rebuild switch --flake .#hierro

# Examples - ARM64 hosts (on-device or via emulation/remote builder):
sudo nixos-rebuild switch --flake .#rpi3
sudo nixos-rebuild switch --flake .#xpi-s905x3

# Build without activating
sudo nixos-rebuild build --flake .#hostname

# Test (activate for current boot only)
sudo nixos-rebuild test --flake .#hostname

# Build/deploy a host remotely
nixos-rebuild switch --flake .#hostname --target-host user@hostname --use-remote-sudo
```

#### Checking & rolling back

```bash
# Show what would be built/changed
sudo nixos-rebuild dry-activate --flake .#hostname

# Show system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Roll back to previous generation
sudo nixos-rebuild switch --rollback
```

### macOS System (Darwin)

For `work-laptop` (aarch64-darwin):

```bash
darwin-rebuild switch --flake .#work-laptop   # apply
darwin-rebuild build  --flake .#work-laptop   # build only
darwin-rebuild check  --flake .#work-laptop   # check
darwin-rebuild generations                    # list generations
darwin-rebuild switch --rollback              # roll back
```

### Standalone Home Manager (non-NixOS Linux)

Two standalone home-manager configurations are provided:
- `superfer@devdesktop` — x86_64 Ubuntu
- `ubuntu@amp1` — aarch64 Ubuntu (also a remote ARM builder)

```bash
# Apply
home-manager switch --flake .#superfer@devdesktop
home-manager switch --flake .#ubuntu@amp1

# Build only / dry run
home-manager build   --flake .#superfer@devdesktop
home-manager dry-run --flake .#superfer@devdesktop

# Generations / rollback
home-manager generations
home-manager switch --rollback
```

If you don't have home-manager installed: `nix shell nixpkgs#home-manager`.

`amp1` is normally deployed remotely with deploy-rs — see below.

### Deployment

This flake exposes **two** deployment tools, both runnable directly from the flake:

#### Colmena (NixOS hosts)

```bash
nix run .#colmena -- apply              # deploy to all NixOS hosts
nix run .#colmena -- apply --on butthead
nix run .#colmena -- apply --on butthead --on blacktop
nix run .#colmena -- build              # build without deploying
nix run .#colmena -- apply --dry-run    # show plan
nix run .#colmena -- exec --on hierro uptime
```

All NixOS hosts are registered as Colmena nodes. The SD-card ARM hosts `rpi3`,
`pine64` and `xpi-s905x3` have `targetHost = null` (flash + build on-device
rather than SSH push). `z-turn` instead sets `targetHost = z-turn.netbird.cloud`,
so once it's booted and on the mesh it's deployed like any other host — built
(cross-compiled) on x86 and pushed over SSH. Colmena deploys via SSH as root;
ensure SSH keys are configured.

#### deploy-rs (home-manager on foreign distros)

`deploy-rs` handles home-manager activations on non-NixOS hosts (currently
`amp1` over Netbird):

```bash
nix run .#deploy -- .#amp1     # deploy ubuntu@amp1 home-manager profile
nix run .#deploy               # deploy all deploy-rs nodes
```

`deploy-rs` validators also run as part of `nix flake check`.

### ARM Single-Board Computers

Supported devices with bootable SD card image generation:
- **Raspberry Pi 3** (`rpi3`) — RPi 3B/3B+ in 64-bit mode (aarch64)
- **Pine64** (`pine64`) — aarch64
- **Amlogic S905X3** (`xpi-s905x3`) — generic S905X3 TV box (aarch64)
- **MYIR Z-turn** (`z-turn`) — Xilinx Zynq-7020 FPGA SoC (**armv7l**), built
  with the `linux-xlnx`/`u-boot-xlnx` forks (u-boot SPL acts as the FSBL — no
  Vivado needed)

#### Build hosts

- **aarch64 boards** (`rpi3`, `pine64`, `xpi-s905x3`) build natively on the
  `amp1` aarch64 remote builder, or via aarch64 emulation on x86 hosts that use
  the `development` module (`boot.binfmt.emulatedSystems = [ "aarch64-linux" ]`).
- **`z-turn` is cross-compiled** from x86 (there is no armv7l builder and the
  repo avoids QEMU binfmt) — so it builds as ordinary x86 work, no emulation.
  The first build compiles the armv7l world from source (no upstream armv7l
  cache); results are then cached on the netbird `nix-serve`.

#### Building SD card images

```bash
nix build .#images.rpi3
nix build .#images.pine64
nix build .#images.xpi-s905x3
nix build .#images.z-turn          # cross-compiled armv7l; long first build

ls -lh result/sd-image/*.img.zst
```

First emulated builds are slow (10–50× slower than native); subsequent builds
use the binary cache.

#### Writing an image

```bash
# Decompress and write in one go (replace /dev/sdX with your card)
zstd -dc result/sd-image/*.img.zst | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync
```

For `z-turn`, set the board's boot-mode jumper to **SD** and attach a serial
console at `ttyPS0` 115200 to watch u-boot SPL → u-boot → extlinux → NixOS.

#### Root filesystem: btrfs, grown on first boot

All SD images build a **btrfs** root directly (zstd compression), generically
via `flake-modules/system-modules/sd-image-btrfs.nix` (wired into every
`sdImage = true` host by `lib/mk-host.nix`):

- The root partition is created with `make-btrfs-fs`, sized to its contents.
- On first boot the partition is grown to fill the card (`boot.growPartition`)
  and the btrfs is grown onto it (`x-systemd.growfs`).

There is no longer an ext4 stage or first-boot conversion. The dual-output
mechanism (regular config vs. `sd-image.nix`) is described in
[the FAQ](#how-the-dual-output-sd-card-image-system-works).

#### Embedded optimizations

ARM hosts use `flake-modules/system-modules/embedded.nix`: lighter package set,
larger zram swap, serial console (`ttyAMA0` for RPi3, `ttyS0` for Pine64/S905X3,
`ttyPS0` for the Zynq `z-turn`), no x86-specific hardware, and aggressive GC /
journald limits for SD longevity.

### Updating Dependencies

```bash
# Update all inputs
nix flake update

# Update a specific input
nix flake update nixpkgs
nix flake update home-manager nixos-hardware sops-nix

# Inspect inputs
nix flake metadata
```

Key inputs: `nixpkgs` (26.05), `nixpkgs-unstable`, `nixpkgs-master`,
`home-manager`, `flake-parts`, `import-tree`, `nixos-hardware`, `nix-darwin`,
`sops-nix`, `colmena`, `deploy-rs`, `quadlet-nix`, `airspy-adsb-bin`.

### Inspecting flake outputs

```bash
nix flake show     # all configurations, images, packages, deploy nodes, …
nix flake check    # evaluate + run deploy-rs checks
```

## Working with the configuration

### Adding a host

1. Create `flake-modules/hosts/<name>.nix` that composes
   `config.flake.modules.nixos.default` plus any opt-in features and registers
   `flake.nixosConfigurations.<name>` (and `flake.colmenaNodes.<name>`).
2. Put machine-specific files (hardware config, host tweaks) under
   `hosts/<name>/nixos/` and import them with `"${inputs.self}/hosts/<name>/nixos"`.
3. For ARM SBCs, also add `flake.images.<name>` and a `hosts/<name>/nixos/sd-image.nix`.

import-tree picks the file up automatically — no central list to edit.

### Adding a feature module

- **NixOS**: create a file under `flake-modules/system-modules/` that writes to
  `flake.modules.nixos.<name>`, then add `config.flake.modules.nixos.<name>` to
  the hosts that want it. Always-on behavior goes in `flake-modules/system/`
  (merged into `…nixos.default`).
- **home-manager**: same pattern under `flake-modules/home-modules/`
  (opt-in) or `flake-modules/home/` (always-on), targeting
  `flake.modules.homeManager.<name>`.

### Custom modules in this configuration

#### Foundation — always-on (`flake-modules/system/`)

`base`, `nix`, `networking`, `netbird`, `users`, `security`, `sops`, `services`,
`podman`, `seedlink`, `socks-proxy`, `distributed-build`, `home-manager`,
`external-modules`.

#### Opt-in NixOS features (`flake-modules/system-modules/`)

- **`desktop.nix`**: Wayland desktop (Niri/Sway, greeter, Steam)
- **`laptop.nix`**: Laptop power management / touchpad
- **`development.nix`**: Dev tools, embedded programming, aarch64 emulation
- **`emulation.nix`**: Retro-gaming emulation (RetroArch, MAME, …)
- **`embedded.nix`**: ARM/SBC optimizations
- **`sd-image-btrfs.nix`**: generic btrfs root for all SD-image hosts (creator,
  filesystems, grow-on-boot), auto-wired by `lib/mk-host.nix`
- **`media-services.nix`** / **`media-podman.nix`**: media server stack and the
  shared rootless `media-podman` user/group
- **`download-services.nix`**: download clients
- **`quadlet-containers.nix`**: declarative rootless Podman containers (media
  stack, Gluetun VPN, utilities) via quadlet-nix
- **`tdarr.nix`** / **`tdarr-worker.nix`**: Tdarr transcoding server / worker
- **`adsb-readsb.nix`** / **`adsb-feeders.nix`**: ADS-B receiver and feeders
- **`novasdr.nix`**: RTL-SDR / NovaSDR web interface
- **`openclaw.nix`**: self-hosted OpenClaw service
- **`backup.nix`**: Kopia snapshot backups
- **`storagebox-mount.nix`**: Hetzner Storage Box CIFS mount
- **`network-watchdog.nix`**: reboot on prolonged connectivity loss
- **`nfs-mounts.nix`**: automated NFS mounts
- **`systemd-nspawn.nix`**: systemd container support
- **`tgtg-watcher.nix`**: Too Good To Go monitoring service

#### Opt-in home-manager features (`flake-modules/home-modules/`)

`niri`, `sway`, `hyprlock`, `kanshi`, `fish`, `zsh`, `wezterm`, `zellij`,
`git`, `gpg`/`gpg-agent`, `keychain`, `mpd`, `beets`, `tidalcycles`,
`nethack`, `ideavim`, `android-tools`, `atuin-server`, `dev-heavy`.

### Overlays

Custom overlays live in `overlays/` and are exposed via
`flake-modules/overlays.nix`. Keep any patches alongside them.

# Troubleshooting / FAQ

## Nix says my repo files don't exist, even though they do!

Nix flakes only see files tracked by git, so `git add .` first. Files in
`.gitignore` are invisible to nix — this keeps builds reproducible.

## Nix installs the wrong version / can't find new software

Dependencies follow `flake.lock`. Run `nix flake update` to refresh.

## ARM images fail to build with "unsupported system"

Enable aarch64 emulation on the build host (or build via the `amp1` aarch64
remote builder):

1. Add `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];`
2. Rebuild: `sudo nixos-rebuild switch`
3. Verify: `cat /proc/sys/fs/binfmt_misc/qemu-aarch64`

Hosts with the `development` module already enable this.

## How the dual-output SD card image system works

ARM devices use a dual-output approach:

1. **SD image config** (`hosts/<name>/nixos/sd-image.nix` + the shared
   `sd-image-btrfs-build` module): imported only when building
   `flake.images.<name>`; produces a bootable **btrfs** image sized to its
   contents. Not used in normal rebuilds.
2. **Regular config** (`hosts/<name>/nixos/` + the dendritic feature modules):
   the actual running system — the same **btrfs** root with compression, managed
   via Colmena and `nixos-rebuild`.
3. **Grow on first boot**: the shared `sd-image-btrfs` module enables
   `boot.growPartition` + `x-systemd.growfs`, so the root partition and btrfs
   expand to fill the card on the first boot — no ext4 stage or conversion.

This gives easy initial deployment (write the SD image), full ongoing
configuration management, and an optimal compressed btrfs root.
