#!/usr/bin/env bash
# Regenerate lib/build-keys.nix (SSH host keys + nix-serve store signing keys
# for the distributed-build fleet) by probing the builders over the mesh.
# Only needed when a builder's host key or nix-serve key rotates.
set -euo pipefail

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$DIR/.."
OUTPUT_FILE="$PROJECT_ROOT/lib/build-keys.nix"

HOSTS=("butthead" "hierro" "tungsten" "elitedex" "lenovix" "falk1")
DOMAIN="netbird.cloud"

echo "Fetching keys for distributed builds..."
echo "Output file: $OUTPUT_FILE"

cat <<'EOF' > "$OUTPUT_FILE"
{ lib, ... }:
{
  # Shared SSH pubkey for the role account `nix-ssh` on every builder.
  # Private half lives in secrets/nix-builder.yaml as a sops secret deployed to
  # /run/secrets/nix-builder-key. Safe to share because nix-ssh's forced command
  # is locked to `nix-daemon --stdio --option builders ""` (see
  # flake-modules/system/distributed-build.nix) — inbound builds only, no
  # re-delegation.
  nixBuilderPublicKey =
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIET73bXt5BAGlLTmYQh4JZGq6I3cfAUoihP/nk+KqQZo nix-builder@fleet";

  keys = {
EOF

for host in "${HOSTS[@]}"; do
    fqdn="${host}.${DOMAIN}"
    echo "--------------------------------------------------"
    echo "Processing $fqdn..."

    # Fetch SSH host key (ed25519); store just the base64 blob.
    echo "  Fetching SSH host key..."
    ssh_host_key=$(ssh-keyscan -t ed25519 "$fqdn" 2>/dev/null | grep "ssh-ed25519" | awk '{print $3}' | head -n1 || echo "")

    if [ -z "$ssh_host_key" ]; then
        echo "  ERROR: Could not fetch SSH key for $fqdn. Is the host up?"
    else
        echo "  Got SSH key: ${ssh_host_key:0:20}..."
    fi

    # Fetch nix store signing key (created on first nix-serve run).
    echo "  Fetching Nix store signing key..."
    nix_store_key=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 "z-247@$fqdn" "cat /var/lib/nix-serve/cache-pub-key.pem" 2>/dev/null || echo "")

    if [ -z "$nix_store_key" ]; then
        echo "  WARNING: Could not fetch Nix signing key for $fqdn."
    else
        echo "  Got Nix key: ${nix_store_key:0:20}..."
    fi

    cat <<EOF >> "$OUTPUT_FILE"
    $host = {
      hostPublicKey = "${ssh_host_key}";
      nixPublicKey = "${nix_store_key}";
    };
EOF

done

cat <<EOF >> "$OUTPUT_FILE"
  };
}
EOF

echo "Done. Written to $OUTPUT_FILE"
echo "NOTE: review the diff — tungsten's nixPublicKey historically embeds the"
echo "old 'blacktop.netbird.cloud' name; only update entries that actually rotated."
