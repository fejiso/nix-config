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

> **Note for replicators**: this flake will **not** evaluate as-is for you.
> Secrets, ingress domains, and ACME email live in a private `private` flake
> input you don't have access to. See [docs/REPLICATING.md](docs/REPLICATING.md)
> for how to wire up your own private repo — or strip the sops/ingress/authelia
> modules entirely.

## What this provides

This flake-based configuration supports:

- **x86_64 NixOS systems**: `elitedex`, `lenovix`, `hispanas`, `a8`, `blacktop`,
  `tungsten`, `hierro`, `falk1`, `butthead`, `snuffles`
- **ARM NixOS systems**: `rpi3` (Raspberry Pi 3), `pine64` (Pine64 SBC),
  `xpi-s905x3` (Amlogic S905X3 TV box) — all aarch64 — plus `z-turn`
  (MYIR Z-turn, Xilinx Zynq-7020 FPGA SoC, **armv7l**, cross-compiled with the
  `linux-xlnx` / `u-boot-xlnx` forks) and `kr260` (AMD/Xilinx KR260, Zynq
  UltraScale+ ZU2EG, **aarch64**, cross-compiled with the `linux-xlnx` ZynqMP
  defconfig; boots off the on-board QSPI firmware)
- **macOS system**: `work-laptop` (aarch64-darwin, via nix-darwin)
- **Standalone home-manager configurations** (non-NixOS Linux):
  `superfer@devdesktop` (x86_64 Ubuntu)
- **SD card image generation**: Bootable **btrfs** images for ARM single-board
  computers (`rpi3`, `pine64`, `xpi-s905x3`, `z-turn`)
- **Cross-platform support**: aarch64/x86_64 on both Linux and Darwin

## Channels & toolchain

- **nixpkgs**: `nixos-26.05` (stable), with `nixpkgs-unstable` reserved
  for explicit per-package exceptions
- **home-manager**: `release-26.05`, using the same stable nixpkgs by default
- **Deployment**: [Colmena](https://github.com/zhaofengli/colmena) for NixOS
  hosts and [deploy-rs](https://github.com/serokell/deploy-rs) for
  home-manager activations on foreign distros
- **Containers**: rootless Podman managed declaratively with
  [quadlet-nix](https://github.com/SEIAROTg/quadlet-nix)
- **Secrets**: [sops-nix](https://github.com/Mic92/sops-nix) — secrets and
  the ingress domain registry live in a **separate private repo**
  (`nix-config-private`), pulled in as the `private` flake input
- **OpenWrt routers**: declarative fleet management with
  [openwrt-nix/nuci](https://github.com/lonerOrz/openwrt-nix); the router
  models and topology live in the private repo (see `docs/ROUTERS.md` there)

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

- **`secrets/`**: not in this repo — sops-encrypted secrets live in the
  private `nix-config-private` repo (the `private` flake input), alongside
  `ingress-domains.nix` and the sops creation rules (`.sops.yaml`).

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
| `tungsten`   | x86_64-linux    | NixOS           | ThinkPad P16 Gen 2 (iGPU + RTX 3500 Ada), development, tdarr worker, ADS-B |
| `butthead`   | x86_64-linux    | NixOS           | Media/download/container hub (quadlet, nspawn, tdarr) |
| `hierro`     | x86_64-linux    | NixOS           | Build host, development, OpenClaw |
| `falk1`      | x86_64-linux    | NixOS           | Lightweight cloud VPS (`embedded` profile) |
| `hispanas`   | x86_64-linux    | NixOS           | SDR (NovaSDR), desktop, development |
| `snuffles`   | x86_64-linux    | NixOS           | ADS-B receiver + feeders, network-watchdog |
| `a8`         | x86_64-linux    | NixOS           | Minimal base host |
| `rpi3`       | aarch64-linux   | NixOS + SD img  | Raspberry Pi 3, embedded |
| `pine64`     | aarch64-linux   | NixOS + SD img  | Pine64 SBC, embedded |
| `xpi-s905x3` | aarch64-linux   | NixOS + SD img  | Amlogic S905X3 box, embedded |
| `z-turn`     | armv7l-linux    | NixOS + SD img  | MYIR Z-turn (Zynq-7020 FPGA SoC); linux-xlnx/u-boot-xlnx, cross-compiled |
| `kr260`      | aarch64-linux   | NixOS + SD img  | AMD/Xilinx KR260 (Zynq UltraScale+ ZU2EG); linux-xlnx (ZynqMP), cross-compiled; boots off stock QSPI firmware |
| `work-laptop`| aarch64-darwin  | nix-darwin      | macOS work machine |
| `devdesktop` | x86_64-linux    | home-manager    | Standalone HM on Ubuntu (`superfer@devdesktop`) |

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
   foreign distros.
5. **Distributed builds**: x86_64 builders with a `nix-serve` binary cache.
6. **Rootless containers**: declarative Podman via quadlet-nix — media stack
   (Sonarr/Radarr/Lidarr/Prowlarr/Emby/qBittorrent/SABnzbd/Gluetun, …) and
   utility containers, plus systemd-nspawn where needed.
7. **Secrets management**: sops-nix for netbird keys, VPN/API credentials,
   backup passwords, Pushover tokens, etc. — all in the private
   `nix-config-private` repo (see [docs/REPLICATING.md](docs/REPLICATING.md)).
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
13. **Declarative ingress & uptime monitoring**: a fleet-wide service registry
    (`fleet.services` in `flake-modules/fleet-services.nix`) generates nginx
    vhosts (public TLS ingress on butthead, public TLS *backup* ingress on
    hierro) and Gatus health checks (incl. push/heartbeat endpoints for
    backups) on hierro. Onboarding a service = one registry entry.

## Ingress & monitoring

A fleet-wide service registry (`flake-modules/fleet-services.nix`) generates
nginx vhosts (public TLS ingress on butthead, public TLS backup ingress on
hierro) and Gatus health checks. Onboarding a service = one registry entry.

## Usage

Quick reference — full details in [USAGE.md](USAGE.md) (incl. deployment via
Colmena / deploy-rs).

### NixOS Systems

```bash
# Apply configuration (replace hostname with your system name)
sudo nixos-rebuild switch --flake .#hostname

# Build without activating / test for current boot only
sudo nixos-rebuild build --flake .#hostname
sudo nixos-rebuild test  --flake .#hostname

# Build/deploy a host remotely
nixos-rebuild switch --flake .#hostname --target-host user@hostname --use-remote-sudo
```

### macOS System (Darwin)

```bash
darwin-rebuild switch --flake .#work-laptop   # apply
```

### Standalone Home Manager (non-NixOS Linux)

```bash
home-manager switch --flake .#superfer@devdesktop
```

### ARM Single-Board Computers

SD card images for `rpi3`, `pine64`, `xpi-s905x3`, `z-turn`, `kr260` — btrfs
roots grown on first boot, cross-compile/native-builder matrix, flashing
instructions: [ARM-SBC.md](ARM-SBC.md).

### Phones & tablets (Mobile NixOS)

Old Android phones/tablets as headless edge servers (`herolte`, `hammerhead`,
`tissot`; Kindle WIP ports `thor`/`ford`/`austin`/`mustang`), via a
mobile-nixos input and in-repo device ports under `devices/`. All
cross-compiled from x86. See [ANDROID-EDGE-DEVICES.md](ANDROID-EDGE-DEVICES.md)
for the device matrix, build/flash flows, and bring-up notes.

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

Key inputs: `nixpkgs` (26.05), `nixpkgs-unstable`, `home-manager`,
`flake-parts`, `import-tree`, `nixos-hardware`, `nix-darwin`,
`sops-nix`, `colmena`, `deploy-rs`, `quadlet-nix`, `airspy-adsb-bin`,
`private` (secrets + ingress domains, see
[docs/REPLICATING.md](docs/REPLICATING.md)).

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

Moved to [TROUBLESHOOTING.md](TROUBLESHOOTING.md) — git-tracking gotchas,
flake.lock refreshes, ARM "unsupported system", and how the dual-output SD
image system works.
