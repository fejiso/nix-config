#!/usr/bin/env bash
# Render the eval-time domain registry from the sops-encrypted canonical copy.
#
# Why: external domains must not land in this (public) git repo, but nginx
# virtualHosts / ACME cert names are needed at *evaluation* time, before sops
# can decrypt anything. Untracked files are not copied into the flake store,
# so the rendered file is exposed as the `ingress-secrets` flake input
# (path:/var/lib/fleet-secrets, see flake.nix).
#
# One-time setup on each machine that evaluates the flake (workstation,
# hierro nix-builder):
#   sudo install -d -o "$USER" -m 0755 /var/lib/fleet-secrets   # workstation
#   sudo install -d -m 0755 /var/lib/fleet-secrets              # hierro (root)
# and copy the rendered file to hierro (same content; the locked narHash
# must match, so re-run this script and deploy the lock change together).
#
# Re-run after editing `sops secrets/ingress.yaml`. Updates the
# ingress-secrets input's narHash in flake.lock (safe to commit: hashes only).
set -euo pipefail
cd "$(dirname "$0")/.."

dest=/var/lib/fleet-secrets
if [ ! -d "$dest" ] || [ ! -w "$dest" ]; then
  echo "error: $dest missing or not writable. One-time setup:" >&2
  echo "  sudo install -d -o \"\$USER\" -m 0755 $dest" >&2
  exit 1
fi

sops -d --output-type json secrets/ingress.yaml | jq -r '
  "{",
  "  domain = \(.domain | @json);",
  "  meshDomain = \(.mesh_domain | @json);",
  "  acmeEmail = \(.acme_email | @json);",
  "  subdomains = {",
  (.subdomains | to_entries[] | "    \(.key) = \(.value | @json);"),
  "  };",
  "}"
' > "$dest/ingress-domains.nix"
echo "wrote $dest/ingress-domains.nix"

nix flake update ingress-secrets
echo "updated ingress-secrets narHash in flake.lock"
echo
echo "If hierro builds this flake (nix-builder), copy the file there too:"
echo "  scp $dest/ingress-domains.nix root@hierro.netbird.cloud:$dest/"
