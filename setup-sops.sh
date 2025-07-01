#!/usr/bin/env bash

# Setup script for sops-nix with age encryption

set -e

echo "Setting up sops-nix with age encryption..."

# Check if age is installed
if ! command -v age-keygen &> /dev/null; then
    echo "Installing age..."
    nix-shell -p age --run "echo 'age installed temporarily'"
fi

# Create age key directory
AGE_DIR="$HOME/.config/sops/age"
mkdir -p "$AGE_DIR"

# Generate age key if it doesn't exist
AGE_KEY_FILE="$AGE_DIR/keys.txt"
if [ ! -f "$AGE_KEY_FILE" ]; then
    echo "Generating age key..."
    age-keygen -o "$AGE_KEY_FILE"
    echo "Age key generated at: $AGE_KEY_FILE"
else
    echo "Age key already exists at: $AGE_KEY_FILE"
fi

# Extract public key
PUBLIC_KEY=$(grep "public key:" "$AGE_KEY_FILE" | cut -d' ' -f4)
echo "Your public key is: $PUBLIC_KEY"

# Update .sops.yaml with the public key
echo "Updating .sops.yaml with your public key..."
sed -i "s/age1xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx/$PUBLIC_KEY/" .sops.yaml

echo "Now you can encrypt the secrets file with:"
echo "sops secrets/netbird.yaml"

echo ""
echo "After encrypting, you can edit it with:"
echo "sops secrets/netbird.yaml"

echo ""
echo "Setup complete! Remember to:"
echo "1. Encrypt the secrets file: sops secrets/netbird.yaml"
echo "2. Commit your changes to git"
echo "3. Deploy to your NixOS hosts"
