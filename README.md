# Multi-Platform Nix Configuration

This repository contains a comprehensive Nix configuration for managing multiple systems across different platforms:
- NixOS (Linux) - x86_64 and ARM64 (aarch64)
- macOS (via nix-darwin)
- Non-NixOS Linux systems (via standalone home-manager)
- ARM single-board computers with SD card image generation

## What this provides

This flake-based configuration supports:

- **x86_64 NixOS systems**: `elitedex`, `lenovix`, `hispanas`, `a8`, `blacktop`, `hierro`, `butthead`, `snuffles`
- **ARM64 NixOS systems**: `rpi3` (Raspberry Pi 3), `pine64` (Pine64 SBC)
- **macOS system**: `work-laptop` (aarch64-darwin)
- **Standalone home-manager configurations**: for non-NixOS Linux systems (`devdesktop`)
- **SD card image generation**: Bootable images for ARM single-board computers
- **Cross-platform support**: for aarch64/x86_64 on both Linux and Darwin

# Repository Structure

This configuration is organized as follows:

- **hosts/**: Contains system-specific configurations
  - **common/**: Shared configurations for all systems
    - **nixos/**: Common NixOS configurations
    - **home/**: Common home-manager configurations
  - **elitedex/**, **lenovix/**, **hispanas/**, **a8/**, **blacktop/**, **hierro/**, **butthead/**, **snuffles/**: x86_64 NixOS system configurations
  - **rpi3/**, **pine64/**: ARM64 NixOS system configurations with SD card image support
  - **work-laptop/**: macOS (Darwin) configuration
  - **devdesktop/**: Standalone home-manager configuration

- **modules/**: Custom modules
  - **nixos/**: NixOS modules
  - **home-manager/**: Home-manager modules
  - **darwin/**: Darwin modules

- **overlays/**: Custom package overlays

- **secrets/**: Encrypted secrets managed by sops-nix

## Key Features

This configuration includes:

1. **Multi-platform support**: Works across NixOS (x86_64 & ARM64), macOS, and non-NixOS Linux systems
2. **ARM/Embedded support**: SD card image generation for Raspberry Pi 3 and Pine64 with automatic btrfs conversion
3. **Nixpkgs channels**: Uses nixos-25.11 stable with access to unstable when needed
4. **Secrets management**: Integrated with sops-nix for secure secrets handling
5. **Hardware support**: Leverages nixos-hardware for optimized hardware configurations (including Raspberry Pi 3)
6. **Custom modules**: Organized modular configuration for both NixOS and home-manager
7. **Custom overlays**: Package modifications and additions
8. **Special packages**: Integration with airspy-adsb-bin for ADS-B tracking
9. **Desktop environment**: Niri window manager with Waybar status bar
10. **Development tools**: Comprehensive development setup with Git, Fish shell, Zellij terminal multiplexer, aarch64 emulation
11. **NFS integration**: Automated NFS mount management
12. **Distributed builds**: Support for distributed Nix builds across systems
13. **Netbird VPN**: Integrated mesh VPN solution
14. **Colmena deployment**: Orchestrated deployment across all NixOS hosts (x86_64 and ARM)

## Usage

### NixOS Systems

This configuration supports multiple NixOS systems:
- **x86_64**: `elitedex`, `lenovix`, `hispanas`, `a8`, `blacktop`, `hierro`, `butthead`, `snuffles`
- **ARM64**: `rpi3` (Raspberry Pi 3), `pine64` (Pine64 single-board computer)

#### Building and Activating NixOS Configurations

```bash
# Apply configuration (replace hostname with your system name)
sudo nixos-rebuild switch --flake .#hostname

# Examples - x86_64 hosts:
sudo nixos-rebuild switch --flake .#elitedex
sudo nixos-rebuild switch --flake .#butthead
sudo nixos-rebuild switch --flake .#hierro

# Examples - ARM64 hosts:
sudo nixos-rebuild switch --flake .#rpi3
sudo nixos-rebuild switch --flake .#pine64

# Build without activating
sudo nixos-rebuild build --flake .#hostname

# Test configuration (builds and activates temporarily for current boot only)
sudo nixos-rebuild test --flake .#hostname

# Build for a specific system remotely
nixos-rebuild build --flake .#hostname --target-host user@hostname --use-remote-sudo
```

#### Checking NixOS Configuration

```bash
# Show what would be built/changed
sudo nixos-rebuild dry-activate --flake .#hostname

# Show system generations
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# Roll back to previous generation
sudo nixos-rebuild switch --rollback
```

### ARM Single-Board Computers (Raspberry Pi 3 & Pine64)

This configuration includes support for ARM single-board computers with bootable SD card image generation.

#### Supported Devices

- **Raspberry Pi 3** (`rpi3`): Full Raspberry Pi 3B/3B+ support using 64-bit mode (aarch64)
- **Pine64** (`pine64`): Pine64 single-board computer support

#### Prerequisites: Enable ARM64 Emulation

Before building SD card images, enable aarch64 emulation on your x86_64 build machine. This is automatically enabled on hosts with `development.enable = true`:
- `blacktop`
- `butthead`
- `hierro`

The emulation uses QEMU binfmt and is configured in `modules/nixos/development.nix`:
```nix
boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
```

After enabling, rebuild your system:
```bash
sudo nixos-rebuild switch --flake .#hostname
```

#### Building SD Card Images

Build compressed SD card images (`.img.zst` format):

```bash
# Build Raspberry Pi 3 SD image (takes 1-4 hours on first build with emulation)
nix build .#images.rpi3

# Build Pine64 SD image
nix build .#images.pine64

# Images are created in result/sd-image/
ls -lh result/sd-image/*.img.zst
```

**Note:** First build will be slow due to QEMU emulation (10-50x slower than native). Subsequent builds use the Nix binary cache and are much faster.

#### Writing SD Card Images

Write the image to an SD card (replace `/dev/sdX` with your actual SD card device):

```bash
# Decompress and write in one command
zstd -d result/sd-image/nixos-rpi3-*.img.zst -c | sudo dd of=/dev/sdX bs=4M status=progress conv=fsync

# Or decompress first, then write
unzstd result/sd-image/nixos-rpi3-*.img.zst
sudo dd if=nixos-rpi3-*.img of=/dev/sdX bs=4M status=progress conv=fsync
```

#### First Boot and Automatic btrfs Conversion

The SD images boot with **ext4** initially, but automatically convert to **btrfs** on first boot:

1. **First boot**: System boots from ext4 SD card image
2. **Conversion trigger**: A systemd service detects ext4 and prepares conversion
3. **Automatic reboot**: System reboots after 5 seconds
4. **Second boot**: During initrd, `btrfs-convert` runs:
   - Filesystem is converted from ext4 to btrfs
   - A `@` subvolume is created
   - All files are moved into the subvolume
   - Compression is enabled (zstd)
5. **Normal operation**: System continues with btrfs + compression

The conversion is handled by `modules/nixos/btrfs-convert-firstboot.nix` and only runs once. The original ext4 filesystem is kept in `ext2_saved/` directory for rollback if needed.

#### Ongoing Management

After initial boot and network configuration, ARM systems can be managed like any other NixOS host:

**Via Colmena (recommended):**
```bash
# Deploy configuration updates
colmena deploy --on rpi3
colmena deploy --on pine64

# Deploy to all hosts
colmena deploy
```

**Via nixos-rebuild (on device):**
```bash
ssh z-247@rpi3
sudo nixos-rebuild switch --flake github:yourusername/nix-config#rpi3
```

**Via remote rebuild:**
```bash
nixos-rebuild switch --flake .#rpi3 --target-host rpi3 --use-remote-sudo
```

#### Features Enabled on ARM Hosts

ARM hosts inherit all common features through `hosts/common/nixos/`:
- User accounts (z-247) with SSH keys
- Netbird mesh VPN (automatically connects to 100.107.0.0/16 network)
- NFS mounts (if enabled)
- SOPS secrets management
- Home-manager integration
- All system services and configurations

**Embedded-specific optimizations** (via `modules/nixos/embedded.nix`):
- Lighter system packages (wine and x86-specific tools removed)
- Increased zram swap (50% vs 10% for better performance on limited RAM)
- Serial console configuration (ttyAMA0 for RPi3, ttyS0 for Pine64)
- Disabled x86-specific hardware support (Intel graphics, 32-bit compatibility)
- Aggressive garbage collection and journald limits
- Optimized for SD card longevity

#### ARM-Specific Configuration Files

Each ARM host has:
- `default.nix`: Main configuration with embedded optimizations
- `hardware-configuration.nix`: Platform-specific settings (kernel, filesystem, firmware)
- `sd-image.nix`: SD image generation settings (only used during image build)
- `home/default.nix`: User home-manager configuration

#### Troubleshooting ARM Builds

**Build fails with "unsupported system":**
- Ensure `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` is enabled on build host
- Rebuild build host after enabling emulation

**SD card won't boot:**
- Verify SD card was written correctly: `sudo fdisk -l /dev/sdX`
- Try a different SD card (use high-quality cards: SanDisk Extreme, Samsung EVO)
- Check serial console output for boot messages

**btrfs conversion fails:**
- Boot into recovery and manually run: `btrfs-convert /dev/mmcblk0p2`
- Check available space (conversion needs ~20% free space)
- If conversion fails, system remains on ext4 and still works

### macOS System (Darwin)

For the macOS system (`work-laptop` on aarch64-darwin):

#### Building and Activating Darwin Configuration

```bash
# Apply configuration
darwin-rebuild switch --flake .#work-laptop

# Build without activating
darwin-rebuild build --flake .#work-laptop

# Check what would be built/changed
darwin-rebuild check --flake .#work-laptop
```

#### Managing Darwin Generations

```bash
# List generations
darwin-rebuild generations

# Roll back to previous generation
darwin-rebuild switch --rollback
```

### Standalone Home Manager

For non-NixOS Linux systems, this configuration supports one host: `devdesktop` (for user `superfer`).

#### Building and Activating Home Manager Configurations

```bash
# For superfer user on devdesktop
home-manager switch --flake .#superfer@devdesktop

# Build without activating
home-manager build --flake .#username@hostname

# Show what would be built/changed
home-manager dry-run --flake .#username@hostname
```

If you don't have home-manager installed, you can install it with:
```bash
nix shell nixpkgs#home-manager
```

#### Managing Home Manager Generations

```bash
# List generations
home-manager generations

# Roll back to previous generation
home-manager switch --rollback
```

### Colmena Deployment

This configuration includes Colmena for orchestrated deployment across all NixOS hosts (both x86_64 and ARM).

#### Deploying to All Hosts

```bash
# Deploy to all hosts in parallel
colmena apply

# Build configurations without deploying
colmena build

# Show deployment plan
colmena apply --dry-run
```

#### Deploying to Specific Hosts

```bash
# Deploy to a single host
colmena apply --on hostname

# Deploy to multiple hosts
colmena apply --on host1 --on host2 --on host3

# Examples
colmena apply --on rpi3
colmena apply --on butthead --on blacktop
```

#### Colmena Node Information

```bash
# Show information about all nodes
colmena node-info

# Show evaluation output for a specific node
colmena eval -E '{nodes, ...}: nodes.rpi3.config.networking.hostName'
```

#### Registered Colmena Hosts

All NixOS hosts are registered in Colmena:
- **x86_64**: elitedex, lenovix, hispanas, a8, blacktop, hierro, butthead, snuffles
- **ARM64**: rpi3, pine64

Colmena deploys via SSH as root. Ensure SSH keys are properly configured for remote access.

### Updating Dependencies

To update all flake inputs to their latest versions:
```bash
nix flake update
```

To update a specific input:
```bash
nix flake lock --update-input nixpkgs
nix flake lock --update-input home-manager
nix flake lock --update-input nixos-hardware
nix flake lock --update-input nix-darwin
nix flake lock --update-input sops-nix
nix flake lock --update-input airspy-adsb-bin
```

To check the status of your inputs (what's available for update):
```bash
nix flake metadata
nix flake info
```

### Building and Running Specific Packages

You can build and run specific packages defined in your flake:

```bash
# Build a package
nix build .#<package-name>

# Run a package without installing
nix run .#<package-name>

# Enter a development shell with specific packages
nix develop .#<devShell-name>
```

### Checking Flake Outputs

To see all available outputs from your flake:
```bash
nix flake show
```

This will display all available:
- NixOS configurations (x86_64 and ARM64)
- Home Manager configurations
- Darwin configurations
- SD card images (for ARM devices)
- Packages
- Development shells
- Colmena deployment configurations
- And other outputs defined in your flake

# What next?

## Use home-manager as a NixOS module

If you prefer to build your home configuration together with your NixOS one,
it's pretty simple.

Simply remove the `homeConfigurations` block from the `flake.nix` file; then
add this to your NixOS configuration (either directly on
`nixos/configuration.nix` or on a separate file and import it):

```nix
{ inputs, outputs, ... }: {
  imports = [
    # Import home-manager's NixOS module
    inputs.home-manager.nixosModules.home-manager
  ];

  home-manager = {
    extraSpecialArgs = { inherit inputs outputs; };
    users = {
      # Import your home-manager configuration
      your-username = import ../home-manager/home.nix;
    };
  };
}
```

In this setup, the `home-manager` tool will not be installed (see
[nix-community/home-manager#4342](https://github.com/nix-community/home-manager/pull/4342)).
To rebuild your home configuration, use `nixos-rebuild` instead.

But if you want to install the `home-manager` tool anyways, you can add the
package into your configuration:

```nix
# To install it for a specific user
users.users = {
  your-username = {
    packages = [ inputs.home-manager.packages.${pkgs.system}.default ];
  };
};

# To install it globally
environment.systemPackages =
  [ inputs.home-manager.packages.${pkgs.system}.default ];
```

## Adding more hosts or users

You can organize them by hostname and username on `nixos` and `home-manager`
directories, be sure to also add them to `flake.nix`.

You can take a look at my (beware, here be reproductible dragons)
[configuration repo](https://github.com/misterio77/nix-config) for ideas.

NixOS makes it easy to share common configuration between hosts (you might want
to create a common directory for these), while keeping everything in sync.
home-manager can help you sync your environment (from editor to WM and
everything in between) anywhere you use it. Have fun!

## User password and secrets

You have basically two ways of setting up default passwords:
- By default, you'll be prompted for a root password when installing with
  `nixos-install`. After you reboot, be sure to add a password to your own
  account and lock root using `sudo passwd -l root`.
- Alternatively, you can specify `initialPassword` for your user. This will
  give your account a default password, be sure to change it after rebooting!
  If you do, you should pass `--no-root-passwd` to `nixos-install`, to skip
  setting a password on the root account.

If you don't want to set your password imperatively, you can also use
`passwordFile` for safely and declaratively setting a password from a file
outside the nix store.

There's also [more advanced options for secret
management](https://nixos.wiki/wiki/Comparison_of_secret_managing_schemes),
including some that can include them (encrypted) into your config repo and/or
nix store, be sure to check them out if you're interested.

## Dotfile management with home-manager

Besides just adding packages to your environment, home-manager can also manage
your dotfiles. I strongly recommend you do, it's awesome!

For full nix goodness, check out the home-manager options with `man
home-configuration.nix`. Using them, you'll be able to fully configure any
program with nix syntax and its powerful abstractions.

Alternatively, if you're still not ready to rewrite all your configs to nix
syntax, there's home-manager options (such as `xdg.configFile`) for including
files from your config repository into your usual dot directories. Add your
existing dotfiles to this repo and try it out!

## Try opt-in persistance

You might have noticed that there's impurity in your NixOS system, in the form
of configuration files and other cruft your system generates when running. What
if you change them in a whim to get something working and forget about it?
Boom, your system is not fully reproductible anymore.

You can instead fully delete your `/` and `/home` on every boot! Nix is okay
with a empty root on boot (all you need is `/boot` and `/nix`), and will
happily reapply your configurations.

There's two main approaches to this: mount a `tmpfs` (RAM disk) to `/`, or
(using a filesystem such as btrfs or zfs) mount a blank snapshot and reset it
on boot.

For stuff that can't be managed through nix (such as games downloaded from
steam, or logs), use [impermanence](https://github.com/nix-community/impermanence)
for mounting stuff you to keep to a separate partition/volume (such as
`/nix/persist` or `/persist`). This makes everything vanish by default, and you
can keep track of what you specifically asked to be kept.

Here's some awesome blog posts about it:
- [Erase your darlings](https://grahamc.com/blog/erase-your-darlings)
- [Encrypted BTRFS with Opt-In State on
  NixOS](https://mt-caret.github.io/blog/posts/2020-06-29-optin-state.html)
- [NixOS: tmpfs as root](https://elis.nu/blog/2020/05/nixos-tmpfs-as-root/) and
  [tmpfs as home](https://elis.nu/blog/2020/06/nixos-tmpfs-as-home/)

Note that for `home-manager` to work correctly here, you need to set up its
NixOS module, as described in the [previous section](#use-home-manager-as-a-nixos-module).

## Adding custom packages

Something you want to use that's not in nixpkgs yet? You can easily build and
iterate on a derivation (package) from this very repository.

To add custom packages:

1. Create a `pkgs` directory in the repository root
2. Create a folder with the desired package name inside `pkgs`
3. Add a `default.nix` file containing the derivation
4. Create a `pkgs/default.nix` file to expose your packages

You'll be able to refer to that package from anywhere in your
home-manager/nixos configurations, build them with `nix build .#package-name`,
or bring them into your shell with `nix shell .#package-name`.

See [the manual](https://nixos.org/manual/nixpkgs/stable/) for some tips on how
to package stuff.

## Adding overlays

Found some outdated package on nixpkgs you need the latest version of? Perhaps
you want to apply a patch to fix a behaviour you don't like? Nix makes it easy
and manageble with overlays!

Use the `overlays/default.nix` file for this.

If you're creating patches, you can keep them on the `overlays` folder as well.

See [the wiki article](https://nixos.wiki/wiki/Overlays) to see how it all
works.

## Adding your own modules

Got some configurations you want to create an abstraction of? Modules are the
answer. These awesome files can expose _options_ and implement _configurations_
based on how the options are set.

Create a file for them on either `modules/nixos` or `modules/home-manager`. Be
sure to also add them to the listing at `modules/nixos/default.nix` or
`modules/home-manager/default.nix`.

See [the wiki article](https://nixos.wiki/wiki/Module) to learn more about
them.

### Custom Modules in This Configuration

This configuration includes several custom modules:

#### NixOS Modules (`modules/nixos/`)

- **`desktop.nix`**: Desktop environment configuration (Niri window manager, Steam, GDM)
- **`laptop.nix`**: Laptop-specific settings (TLP power management, touchpad configuration)
- **`development.nix`**: Development tools (PlatformIO, Arduino, embedded programming, aarch64 emulation)
- **`emulation.nix`**: Retro gaming emulation (RetroArch, MAME, Dolphin, etc.)
- **`embedded.nix`**: Optimizations for ARM/embedded devices (lighter packages, increased zram, serial console)
- **`btrfs-convert-firstboot.nix`**: Automatic ext4-to-btrfs conversion on first boot for SD card images
- **`tdarr-worker.nix`**: Tdarr transcoding worker node configuration
- **`media-services.nix`**: Podman-based media services (Sonarr, Radarr, Lidarr, Jellyfin, Emby)
- **`download-services.nix`**: Download clients (qBittorrent, Deluge, SABnzbd)
- **`adsb-readsb.nix`**: ADS-B receiver configuration for flight tracking
- **`adsb-feeders.nix`**: ADS-B data feeders (FlightAware, FlightRadar24, etc.)
- **`nfs-mounts.nix`**: Automated NFS mount management
- **`systemd-nspawn.nix`**: systemd container support
- **`tgtg-watcher.nix`**: Too Good To Go monitoring service

#### Home-Manager Modules (`modules/home-manager/`)

- **`fish.nix`**: Fish shell configuration with custom functions and aliases
- **`git.nix`**: Git configuration with GPG signing
- **`niri.nix`**: Niri Wayland compositor configuration
- **`sway.nix`**: Sway window manager configuration
- **`tidalcycles.nix`**: TidalCycles live coding environment
- **`mpd.nix`**: Music Player Daemon setup
- **`beets.nix`**: Music library management
- **`nethack.nix`**: NetHack game configuration
- **`wezterm.nix`**: WezTerm terminal emulator
- **`zellij.nix`**: Zellij terminal multiplexer
- **`kanshi.nix`**: Dynamic display configuration for Wayland
- **`gpg.nix`** / **`gpg-agent.nix`**: GPG and GPG agent setup
- **`dev-heavy.nix`**: Heavy development tools (Arduino IDE, etc.)

# Troubleshooting / FAQ

## Nix says my repo files don't exist, even though they do!

Nix flakes only see files that git is currently tracked, so just `git add .`
and you should be good to go. Files on `.gitignore`, of course, are invisible
to nix - this is to guarantee your build won't depend on anything that is not
on your repo.

## Nix installs the wrong version of software/fails to find new software

The nix dependencies (such as `nixpkgs`) used by your configuration will
strictly follow the `flake.lock` file, using the commits written into it when
you (re)generated.

To update your flake inputs, simply use `nix flake update`.

## ARM images fail to build with "unsupported system"

Make sure you've enabled aarch64 emulation on your build host:
1. Add `boot.binfmt.emulatedSystems = [ "aarch64-linux" ];` to your configuration
2. Rebuild: `sudo nixos-rebuild switch`
3. Verify: `cat /proc/sys/fs/binfmt_misc/qemu-aarch64`

Alternatively, enable the development module which includes aarch64 emulation:
```nix
development.enable = true;
```

## How the dual-output SD card image system works

This configuration uses a dual-output approach for ARM devices:

1. **SD Image Configuration** (`hosts/*/nixos/sd-image.nix`):
   - Only imported during image builds via `mkSdImageSystem`
   - Creates bootable ext4 SD card images
   - Overrides filesystem settings for initial boot
   - Not used during regular system rebuilds

2. **Regular Configuration** (`hosts/*/nixos/default.nix`):
   - Used for ongoing management after first boot
   - Specifies btrfs with compression
   - Works with Colmena and nixos-rebuild
   - The actual running system configuration

3. **Automatic Conversion**:
   - Bridge between SD image (ext4) and regular config (btrfs)
   - Runs once on first boot
   - Seamlessly converts filesystem without user intervention

This approach allows:
- Easy initial deployment (write SD image)
- Full NixOS configuration management (colmena, nixos-rebuild)
- Optimal filesystem (btrfs with compression)
- No manual conversion steps

<!--
# Learning resources
TODO
-->
