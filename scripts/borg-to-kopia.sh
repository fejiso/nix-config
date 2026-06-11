#!/usr/bin/env bash
# Migrate multiple Borg repositories to a single Kopia repository
# Preserves historical snapshots with proper timestamps and source labels

set -euo pipefail

# Configuration - edit these
KOPIA_REPO="${KOPIA_REPO:-/path/to/kopia-repo}"
WORKDIR="${WORKDIR:-/tmp/borg-migrate}"
BORG_PASSPHRASE="${BORG_PASSPHRASE:-}"

# Define source repos: "label:path"
# Edit this array with your actual repos
BORG_REPOS=(
  "repo1:/path/to/borg/repo1"
  "repo2:/path/to/borg/repo2"
  # Add more repos here
)

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

usage() {
  cat <<EOF
Usage: $0 <command> [options]

Commands:
  check       Check and list all Borg repos
  repair      Attempt to repair damaged repos
  migrate     Migrate all repos to Kopia
  migrate-one <label>  Migrate a single repo

Environment variables:
  KOPIA_REPO       Path to Kopia repository
  WORKDIR          Temporary extraction directory
  BORG_PASSPHRASE  Borg repository passphrase

Example:
  BORG_PASSPHRASE="secret" KOPIA_REPO="/backup/kopia" $0 migrate
EOF
  exit 1
}

check_deps() {
  for cmd in borg kopia jq; do
    if ! command -v "$cmd" &>/dev/null; then
      log_error "Missing dependency: $cmd"
      exit 1
    fi
  done
}

get_repo_path() {
  local label="$1"
  for entry in "${BORG_REPOS[@]}"; do
    local l="${entry%%:*}"
    local p="${entry#*:}"
    if [[ "$l" == "$label" ]]; then
      echo "$p"
      return 0
    fi
  done
  return 1
}

cmd_check() {
  log_info "Checking all Borg repositories..."

  for entry in "${BORG_REPOS[@]}"; do
    local label="${entry%%:*}"
    local repo="${entry#*:}"

    echo ""
    log_info "=== $label ($repo) ==="

    if [[ ! -d "$repo" ]]; then
      log_error "Repository does not exist: $repo"
      continue
    fi

    export BORG_REPO="$repo"

    # Get repo info
    if borg info 2>/dev/null; then
      echo ""
      log_info "Archives:"
      borg list --short | head -20
      local count=$(borg list --short | wc -l)
      if [[ $count -gt 20 ]]; then
        echo "  ... and $((count - 20)) more"
      fi

      echo ""
      log_info "Running integrity check..."
      if borg check 2>&1; then
        log_info "Repository OK"
      else
        log_warn "Repository has issues - run '$0 repair' to fix"
      fi
    else
      log_error "Cannot access repository"
    fi
  done
}

cmd_repair() {
  log_warn "This will attempt to repair damaged repositories."
  log_warn "Make sure you have backups of your Borg repos before proceeding!"
  read -p "Continue? [y/N] " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 0
  fi

  for entry in "${BORG_REPOS[@]}"; do
    local label="${entry%%:*}"
    local repo="${entry#*:}"

    log_info "=== Repairing $label ==="
    export BORG_REPO="$repo"

    if borg check --repair 2>&1; then
      log_info "Repair completed for $label"
    else
      log_error "Repair failed for $label"
    fi
  done
}

migrate_repo() {
  local label="$1"
  local repo="$2"

  log_info "=== Migrating $label from $repo ==="

  export BORG_REPO="$repo"

  # Get list of archives
  local archives
  archives=$(borg list --short --sort-by timestamp)
  local total=$(echo "$archives" | wc -l)
  local current=0

  for archive in $archives; do
    ((current++))
    log_info "[$current/$total] Extracting $archive..."

    # Clean workdir
    rm -rf "${WORKDIR:?}"/*
    mkdir -p "$WORKDIR"

    # Extract archive
    if ! borg extract "::$archive" --target "$WORKDIR" 2>&1; then
      log_error "Failed to extract $archive, skipping..."
      continue
    fi

    # Get original timestamp
    local timestamp
    timestamp=$(borg info "::$archive" --json 2>/dev/null | jq -r '.archives[0].start' || echo "")

    # Build kopia command
    local kopia_args=(
      snapshot create "$WORKDIR"
      --tags="source:$label,borg-archive:$archive"
      --override-source="$label"
    )

    if [[ -n "$timestamp" && "$timestamp" != "null" ]]; then
      kopia_args+=(--start-time="$timestamp")
    fi

    # Create Kopia snapshot
    if ionice -c3 nice -n19 kopia "${kopia_args[@]}" 2>&1; then
      log_info "Migrated: $archive"
    else
      log_error "Failed to create Kopia snapshot for $archive"
    fi
  done

  log_info "Completed migration of $label ($total archives)"
}

cmd_migrate() {
  log_info "Starting migration of all repositories to Kopia"
  log_info "Kopia repo: $KOPIA_REPO"
  log_info "Work directory: $WORKDIR"

  mkdir -p "$WORKDIR"

  # Initialize or connect to Kopia repo
  if [[ ! -d "$KOPIA_REPO" ]]; then
    log_info "Creating new Kopia repository..."
    kopia repository create filesystem --path "$KOPIA_REPO"
  else
    log_info "Connecting to existing Kopia repository..."
    kopia repository connect filesystem --path "$KOPIA_REPO" 2>/dev/null || true
  fi

  # Migrate each repo
  for entry in "${BORG_REPOS[@]}"; do
    local label="${entry%%:*}"
    local repo="${entry#*:}"

    if [[ ! -d "$repo" ]]; then
      log_warn "Skipping $label - repository not found: $repo"
      continue
    fi

    migrate_repo "$label" "$repo"
  done

  # Cleanup
  rm -rf "$WORKDIR"

  log_info "=== Migration Summary ==="
  kopia snapshot list --all
}

cmd_migrate_one() {
  local label="$1"
  local repo

  if ! repo=$(get_repo_path "$label"); then
    log_error "Unknown repository label: $label"
    log_info "Available labels:"
    for entry in "${BORG_REPOS[@]}"; do
      echo "  - ${entry%%:*}"
    done
    exit 1
  fi

  mkdir -p "$WORKDIR"

  # Connect to Kopia
  kopia repository connect filesystem --path "$KOPIA_REPO" 2>/dev/null || \
    kopia repository create filesystem --path "$KOPIA_REPO"

  migrate_repo "$label" "$repo"

  rm -rf "$WORKDIR"
}

# Main
check_deps

case "${1:-}" in
  check)
    cmd_check
    ;;
  repair)
    cmd_repair
    ;;
  migrate)
    cmd_migrate
    ;;
  migrate-one)
    [[ -z "${2:-}" ]] && usage
    cmd_migrate_one "$2"
    ;;
  *)
    usage
    ;;
esac
