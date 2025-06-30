# Multi-Platform Nix Configuration

This configuration supports multiple systems with shared common configuration:

**System Versions:**
- **NixOS**: 25.05 (stable)
- **Home Manager**: master/unstable (latest features)
- **Darwin**: Following NixOS 25.05

## Systems

### NixOS Systems (Full system + home-manager) - User: z-247
- **elitedex**: Desktop system with GNOME
- **lenovix**: Laptop system with power management
- **a8**: Server/headless system

### Non-NixOS Systems (Home-manager only) - User: superfer
- **devdesktop**: Amazon Linux development machine
- **work-laptop**: macOS laptop with Darwin

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
   # For elitedex
   sudo nixos-rebuild switch --flake .#elitedex
   
   # For lenovix
   sudo nixos-rebuild switch --flake .#lenovix
   
   # For a8
   sudo nixos-rebuild switch --flake .#a8
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
   nix run home-manager/master -- switch --flake .#superfer@devdesktop
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
├── flake.nix                 # Main flake configuration
├── hosts/
│   ├── common/
│   │   ├── nixos/             # Common NixOS configuration
│   │   ├── home-nixos/        # Common home config for NixOS (z-247)
│   │   └── home-standalone/   # Common home config for standalone (superfer)
│   ├── elitedex/
│   │   ├── nixos/           # EliteDX NixOS config
│   │   └── home/            # EliteDX home config
│   ├── lenovix/
│   │   ├── nixos/           # Lenovix NixOS config
│   │   └── home/            # Lenovix home config
│   ├── a8/
│   │   ├── nixos/           # A8 NixOS config
│   │   └── home/            # A8 home config
│   ├── devdesktop/
│   │   └── home/            # Amazon Linux home config
│   └── work-laptop/
│       ├── darwin/          # macOS system config
│       └── home/            # macOS home config
├── modules/
│   ├── nixos/               # Custom NixOS modules
│   ├── home-manager/        # Custom home-manager modules
│   └── darwin/              # Custom Darwin modules
├── overlays/                # Nixpkgs overlays
└── pkgs/                    # Custom packages
```

## Customization

### Adding New Hosts

1. Create host directory: `mkdir -p hosts/HOSTNAME/{nixos,home}` (or just `home` for non-NixOS)
2. Add configuration files in the host directory
3. Add the host to `flake.nix` in the appropriate section

### Modifying Common Configuration

- Edit files in `hosts/common/nixos/` for NixOS-wide changes
- Edit files in `hosts/common/home/` for home-manager changes across all systems
- Edit files in `hosts/common/home-standalone/` for home-manager changes across standalone systems (superfer)

### Host-Specific Configuration

- Edit files in `hosts/HOSTNAME/nixos/` for NixOS-specific changes
- Edit files in `hosts/HOSTNAME/home/` for home-manager-specific changes

## Important Notes

1. **Hardware Configuration**: Make sure to replace the placeholder UUIDs in hardware-configuration.nix files with your actual disk UUIDs.

2. **Git Integration**: This configuration assumes git tracking. Make sure to `git add` new files before building.

3. **Secrets Management**: Consider using tools like `sops-nix` or `agenix` for managing secrets across systems.

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
