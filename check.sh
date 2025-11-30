#!/usr/bin/env bash
# Configuration validation script

set -e

echo "🔍 Checking flake configuration..."

# Check if flake is valid
nix --extra-experimental-features 'nix-command flakes' flake check --no-build

echo "✅ Flake configuration is valid!"

echo "📋 Available configurations:"
echo ""
echo "NixOS Systems:"
echo "  - elitedex (desktop)"
echo "  - lenovix (laptop)" 
echo "  - a8 (server)"
echo "  - blacktop (desktop/laptop)"
echo "  - hierro (server)"
echo "  - butthead (desktop/media server)"
echo ""
echo "Home-manager only:"
echo "  - superfer@devdesktop (Amazon Linux)"
echo ""
echo "Darwin systems:"
echo "  - work-laptop (macOS)"
echo ""

echo "🚀 To build a configuration:"
echo "  NixOS: sudo nixos-rebuild switch --flake .#HOSTNAME"
echo "  Home-manager: home-manager switch --flake .#USER@HOSTNAME"
echo "  Darwin: darwin-rebuild switch --flake .#HOSTNAME"
