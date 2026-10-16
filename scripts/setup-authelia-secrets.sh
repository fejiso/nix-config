#!/usr/bin/env bash
# One-time setup: generate secrets/authelia.yaml (sops-encrypted) for the
# Authelia SSO portal (flake-modules/system-modules/authelia.nix).
#
# Prompts for the initial user (argon2id hash via `nix run nixpkgs#authelia`),
# generates the three random secrets, and encrypts in place with sops (matches
# the catch-all `secrets/.*$` rule in .sops.yaml — sops will ask for your
# passphrase). Re-run `sops secrets/authelia.yaml` to edit users later.
set -euo pipefail
cd "$(dirname "$0")/.."

target=secrets/authelia.yaml
if [ -e "$target" ]; then
  echo "error: $target already exists (edit it with: sops $target)" >&2
  exit 1
fi

read -rp "Authelia username [z]: " username; username=${username:-z}
read -rp "Display name [$username]: " display; display=${display:-$username}
read -rp "Email: " email
read -rsp "Password: " password; echo

echo "Hashing password (argon2id, this takes a moment)..."
hash=$(nix run nixpkgs#authelia -- crypto hash generate argon2 --password "$password" \
  | sed -n 's/^Digest: //p')
if [ -z "$hash" ]; then
  echo "error: failed to produce password hash" >&2
  exit 1
fi

rand() { openssl rand -hex 64; }

cleanup() { [ -f "$target" ] && ! grep -q '^sops:' "$target" && shred -u "$target"; }
trap cleanup EXIT

cat > "$target" <<EOF
# Authelia SSO secrets. users_database is the whole file-based user DB as a
# single string (mounted as-is). Add users by appending to it; hash passwords
# with: nix run nixpkgs#authelia -- crypto hash generate argon2
jwt_secret: $(rand)
session_secret: $(rand)
storage_encryption_key: $(rand)
users_database: |
  users:
    ${username}:
      displayname: "${display}"
      password: "${hash}"
      email: ${email}
      groups:
        - admins
EOF

sops --encrypt --in-place "$target"
trap - EXIT
echo "wrote $target (encrypted)"
echo
echo "Next: deploy butthead, browse to the auth portal, and enroll TOTP on"
echo "first login (access policy is two_factor)."
