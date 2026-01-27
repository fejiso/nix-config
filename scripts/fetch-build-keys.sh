#!/usr/bin/env bash
set -euo pipefail

# Directory of this script
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$DIR/.."
OUTPUT_FILE="$PROJECT_ROOT/hosts/common/nixos/build-keys.nix"

HOSTS=("butthead" "hierro" "blacktop" "elitedex" "lenovix")
DOMAIN="netbird.cloud"

echo "Fetching keys for distributed builds..."
echo "Output file: $OUTPUT_FILE"

# Start the Nix file
cat <<EOF > "$OUTPUT_FILE"
{ lib, ... }:
{
  keys = {
EOF

for host in "${HOSTS[@]}"; do
    fqdn="${host}.${DOMAIN}"
    echo "--------------------------------------------------"
    echo "Processing $fqdn..."

    # Fetch SSH Host Key (ed25519)
    # ssh-keyscan outputs: hostname key-type key-base64
    # We want "key-type key-base64" for publicHostKey
    echo "  Fetching SSH host key..."
    ssh_host_key=$(ssh-keyscan -t ed25519 "$fqdn" 2>/dev/null | grep "ssh-ed25519" | awk '{print $2, $3}' | head -n1 || echo "")

    if [ -z "$ssh_host_key" ]; then
        echo "  ERROR: Could not fetch SSH key for $fqdn. Is the host up?"
        ssh_host_key=""
    else
        echo "  Got SSH key: ${ssh_host_key:0:20}..."
    fi

    # Fetch Nix Store Signing Key
    # We use -o StrictHostKeyChecking=no because we might not have added the key yet
    # We assume 'z-247' user can read the file. If not, this might need 'sudo cat' but then we need password/sudoers.
    # The file path is typically /var/lib/nix-serve/cache-pub-key.pem
    echo "  Fetching Nix store signing key..."
    nix_store_key=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "z-247@$fqdn" "cat /var/lib/nix-serve/cache-pub-key.pem" 2>/dev/null || echo "")

    if [ -z "$nix_store_key" ]; then
        echo "  WARNING: Could not fetch Nix signing key for $fqdn."
    else
        echo "  Got Nix key: ${nix_store_key:0:20}..."
    fi

    # Write to file
    cat <<EOF >> "$OUTPUT_FILE"
    $host = {
      hostPublicKey = "${ssh_host_key}";
      nixPublicKey = "${nix_store_key}";
    };
EOF

done

# Close the Nix file
cat <<EOF >> "$OUTPUT_FILE"
  };
}
EOF

echo "Done. Written to $OUTPUT_FILE"
