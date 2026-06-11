#!/usr/bin/env bash
# Configuration validation script

set -e

echo "🔍 Checking flake configuration..."

# Check if flake is valid
nix --extra-experimental-features 'nix-command flakes' flake check --no-build

echo "✅ Flake configuration is valid!"

# List configurations dynamically from the flake outputs so this never goes
# stale as hosts are added/removed.
list() {
  nix eval --raw ".#$1" \
    --apply 'attrs: builtins.concatStringsSep "\n" (map (n: "  - " + n) (builtins.attrNames attrs))'
  echo ""
}

echo "📋 Available configurations:"
echo ""
echo "NixOS Systems:"
list nixosConfigurations
echo ""
echo "Home-manager only:"
list homeConfigurations
echo ""
echo "Darwin systems:"
list darwinConfigurations
echo ""

echo "🚀 To build a configuration:"
echo "  NixOS: sudo nixos-rebuild switch --flake .#HOSTNAME"
echo "  Home-manager: home-manager switch --flake .#USER@HOSTNAME"
echo "  Darwin: darwin-rebuild switch --flake .#HOSTNAME"
