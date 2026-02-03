#!/usr/bin/env bash
set -uo pipefail

REPO_URL="https://github.com/fejiso/nix-config.git"
REPO_DIR="/var/lib/nix-builder/repo"
OUT_DIR="/var/lib/nix-builder"

# Clone or fetch
if [ ! -d "$REPO_DIR/.git" ]; then
  git clone --depth 1 "$REPO_URL" "$REPO_DIR"
else
  git -C "$REPO_DIR" fetch --depth 1 origin master
  LOCAL=$(git -C "$REPO_DIR" rev-parse HEAD)
  REMOTE=$(git -C "$REPO_DIR" rev-parse FETCH_HEAD)
  if [ "$LOCAL" = "$REMOTE" ]; then
    echo "No changes (${LOCAL:0:8}), skipping build"
    exit 0
  fi
  git -C "$REPO_DIR" reset --hard FETCH_HEAD
fi

REV=$(git -C "$REPO_DIR" rev-parse --short HEAD)
echo "Building revision ${REV} ..."

cd "$REPO_DIR"
colmena build

# Pin build results as GC roots
colmena eval -E '{ config, ... }: builtins.toString config.system.build.toplevel' \
  | jq -r 'to_entries[] | "\(.key) \(.value)"' \
  | while read -r host path; do
      nix-store --add-root "${OUT_DIR}/result-${host}" --indirect -r "$path"
    done

echo "All hosts built successfully at revision ${REV}"
