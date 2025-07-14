# Multi-Platform Nix Configuration

This repository contains a comprehensive Nix configuration for managing multiple systems across different platforms:
- NixOS (Linux)
- macOS (via nix-darwin)
- Non-NixOS Linux systems (via standalone home-manager)

## What this provides

This flake-based configuration supports:

- **Multiple NixOS systems**: `elitedex`, `lenovix`, and `a8` (x86_64-linux)
- **macOS system**: `work-laptop` (aarch64-darwin)
- **Standalone home-manager configurations**: for non-NixOS Linux systems (`devdesktop` and `blacktop`)
- **Cross-platform support**: for aarch64/x86_64 on both Linux and Darwin

# Repository Structure

This configuration is organized as follows:

- **hosts/**: Contains system-specific configurations
  - **common/**: Shared configurations for all systems
    - **nixos/**: Common NixOS configurations
    - **home/**: Common home-manager configurations
  - **elitedex/**, **lenovix/**, **a8/**: NixOS system configurations
  - **work-laptop/**: macOS (Darwin) configuration
  - **devdesktop/**, **blacktop/**: Standalone home-manager configurations

- **modules/**: Custom modules
  - **nixos/**: NixOS modules
  - **home-manager/**: Home-manager modules
  - **darwin/**: Darwin modules

- **overlays/**: Custom package overlays

- **secrets/**: Encrypted secrets managed by sops-nix

## Key Features

This configuration includes:

1. **Multi-platform support**: Works across NixOS, macOS, and non-NixOS Linux systems
2. **Nixpkgs channels**: Uses nixos-25.05 stable with access to unstable when needed
3. **Secrets management**: Integrated with sops-nix for secure secrets handling
4. **Hardware support**: Leverages nixos-hardware for optimized hardware configurations
5. **Custom modules**: Organized modular configuration for both NixOS and home-manager
6. **Custom overlays**: Package modifications and additions
7. **Special packages**: Integration with airspy-adsb-bin for ADS-B tracking

## Usage

### NixOS Systems

This configuration supports three NixOS systems: `elitedex`, `lenovix`, and `a8` (all x86_64-linux).

#### Building and Activating NixOS Configurations

```bash
# Apply configuration (replace hostname with elitedex, lenovix, or a8)
sudo nixos-rebuild switch --flake .#hostname

# Examples:
sudo nixos-rebuild switch --flake .#elitedex
sudo nixos-rebuild switch --flake .#lenovix
sudo nixos-rebuild switch --flake .#a8

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

For non-NixOS Linux systems, this configuration supports two hosts: `devdesktop` (for user `superfer`) and `blacktop` (for user `z-247`).

#### Building and Activating Home Manager Configurations

```bash
# For superfer user on devdesktop
home-manager switch --flake .#superfer@devdesktop

# For z-247 user on blacktop
home-manager switch --flake .#z-247@blacktop

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
- NixOS configurations
- Home Manager configurations
- Darwin configurations
- Packages
- Development shells
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

<!--
# Learning resources
TODO
-->
