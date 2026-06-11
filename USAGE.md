# Multi-Platform Nix Configuration

This configuration supports multiple systems with shared common configuration
(dendritic flake-parts layout — see README.md for the full architecture).

**System Versions:**
- **NixOS**: 26.05 (stable, `nixos-26.05`); `nixpkgs-unstable` and
  `nixpkgs-master` are available as extra inputs for selective pinning
- **Home Manager**: `release-26.05`
- **Darwin**: nix-darwin against the same nixpkgs

## Systems

See the "Host roles at a glance" table in README.md for the full list. In
short:

### NixOS systems (full system + home-manager) — user: z-247
`a8`, `blacktop`, `butthead`, `elitedex`, `hierro`, `hispanas`, `lenovix`,
`snuffles`, plus ARM/SD-image hosts `pine64`, `rpi3`, `xpi-s905x3`.

### Non-NixOS systems (home-manager only) — user: superfer/ubuntu
- **devdesktop**: Amazon Linux development machine (`superfer@devdesktop`)
- **amp1**: Ubuntu ARM builder (`ubuntu@amp1`)
- **work-laptop**: macOS laptop with nix-darwin

## Usage

### NixOS Systems

1. **Initial Setup**: Copy your hardware configuration to the appropriate host directory:
   ```bash
   # Generate hardware config
   sudo nixos-generate-config --root /mnt
   # Copy to your host directory
   cp /mnt/etc/nixos/hardware-configuration.nix hosts/HOSTNAME/nixos/
   ```

2. **Build and switch**:
   ```bash
   sudo nixos-rebuild switch --flake .#HOSTNAME
   ```

3. **Remote deployment** (all NixOS hosts at once, or per host):
   ```bash
   colmena apply --on HOSTNAME   # or omit --on for all
   ```

### Amazon Linux (devdesktop)

1. **Install Nix**:
   ```bash
   curl -L https://nixos.org/nix/install | sh
   ```

2. **Enable flakes**:
   ```bash
   mkdir -p ~/.config/nix
   echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf
   ```

3. **Install home-manager and apply config**:
   ```bash
   nix run home-manager -- switch --flake .#superfer@devdesktop
   ```

### macOS (work-laptop)

1. **Install Nix**:
   ```bash
   curl -L https://nixos.org/nix/install | sh
   ```

2. **Install nix-darwin**:
   ```bash
   nix run nix-darwin -- switch --flake .#work-laptop
   ```

3. **Subsequent updates**:
   ```bash
   darwin-rebuild switch --flake .#work-laptop
   ```

## Configuration Structure

```
├── flake.nix                  # Inputs + flake-parts/import-tree bootstrap
├── flake-modules/             # ALL flake logic (auto-imported by import-tree)
│   ├── hosts/<name>.nix       # One file per host (most use lib/mk-host.nix)
│   ├── system/                # Foundation NixOS modules (merged into `default`)
│   ├── system-modules/        # Opt-in NixOS feature modules
│   ├── home/                  # Foundation home-manager modules
│   └── home-modules/          # Opt-in home-manager feature modules
├── hosts/<name>/              # Machine-specific files per host
│   ├── nixos/                 # hardware-configuration.nix + host tweaks
│   ├── home/                  # host-specific home-manager config
│   └── darwin/                # (work-laptop only) macOS system config
├── lib/                       # mk-host.nix and other helpers
├── overlays/                  # Nixpkgs overlays + patches
├── scripts/                   # Maintenance scripts (snapraid, builders, …)
└── secrets/                   # sops-nix encrypted secrets
```

## Customization

### Adding New Hosts

1. Create the host directory: `mkdir -p hosts/HOSTNAME/nixos` (plus `home/` if
   it has host-specific home-manager config) and add
   `hardware-configuration.nix` + `default.nix` there.
2. Create `flake-modules/hosts/HOSTNAME.nix` using the helper:
   ```nix
   { inputs, config, ... }:
   import ../../lib/mk-host.nix {
     inherit inputs config;
     name = "HOSTNAME";
     modules = [ /* opt-in flake.modules.nixos.* */ ];
   }
   ```
   It is auto-imported by import-tree — no flake.nix changes needed.
3. `git add` the new files (flakes only see tracked files), then build.

### Modifying Common Configuration

- `flake-modules/system/` for changes to every NixOS host
- `flake-modules/system-modules/` for opt-in NixOS features
- `flake-modules/home/` for home-manager changes across all systems
- `flake-modules/home-modules/` for opt-in home-manager features

### Host-Specific Configuration

- Edit files in `hosts/HOSTNAME/nixos/` for NixOS-specific changes
- Edit files in `hosts/HOSTNAME/home/` for home-manager-specific changes

## Important Notes

1. **Hardware Configuration**: Make sure to replace the placeholder UUIDs in hardware-configuration.nix files with your actual disk UUIDs.

2. **Git Integration**: This configuration assumes git tracking. Make sure to `git add` new files before building.

3. **Secrets Management**: Secrets are managed with sops-nix (see
   `secrets/` and `.sops.yaml`; bootstrap a new machine with `setup-sops.sh`).

4. **Updates**: Run `nix flake update` to update all inputs, then rebuild your systems.

## Troubleshooting

- If you get "file not found" errors, make sure all files are tracked by git (`git add .`)
- For permission issues on macOS, you may need to enable the nix-daemon
- On Amazon Linux, make sure the nix daemon is running and your user is in the nix-users group

## Included Tools

### Shell & Terminal
- **Fish**: Modern shell with autocompletion and syntax highlighting (default)
- **Zsh**: Alternative shell with Oh My Zsh
- **Bash**: Fallback shell
- **Zellij**: Terminal multiplexer (alternative to tmux)
- **Starship**: Cross-shell prompt

### File & Text Tools
- **Helix**: Modern modal text editor
- **Bat**: Cat clone with syntax highlighting
- **Eza**: Modern ls replacement
- **Ripgrep**: Fast text search tool
- **Fd**: Fast find alternative
- **Broot**: Interactive tree view and file manager
- **Zoxide**: Smart cd command that learns your habits

### Development Tools
- **Direnv**: Environment variable management per directory
- **Git**: Version control with GitHub CLI (gh)
- **Neovim**: Advanced text editor
- **Various language tools**: Python, Node.js, Go, Rust, etc.

### System Utilities
- **SSH**: Server enabled on all NixOS systems, agent on all systems
- **Docker**: Container runtime (NixOS systems)
- **Various CLI tools**: htop, tree, wget, curl, jq, etc.

### Useful Aliases
All systems include these convenient aliases:
- `ll` → `eza -l` (detailed list)
- `la` → `eza -la` (all files, detailed)
- `ls` → `eza` (modern ls)
- `cat` → `bat` (syntax highlighted cat)
- `grep` → `rg` (ripgrep)
- `find` → `fd` (fast find)
- `cd` → `z` (zoxide smart cd)

### Quick Start Commands
After installation, try these commands:
- `hx` - Open Helix editor
- `zj` - Start Zellij terminal multiplexer
- `br` - Open Broot file manager
- `rg "search term"` - Search for text in files
- `z /path` - Smart navigate to frequently used directories
- `bat filename` - View file with syntax highlighting
