#!/usr/bin/env bash
# bcachefs-module-swap.sh — butthead: swap the bcachefs kernel module without
# rebooting (unmount pool -> rmmod/modprobe -> remount), restarting everything
# that uses /mnt/user around it.
#
# Run AFTER deploying the bcachefs 1.39.6 pin (colmena apply --on butthead)
# and WITHOUT a nix flake update (running kernel must match the built module).
#
# Usage: sudo bash scripts/bcachefs-module-swap.sh [path-to-bcachefs.ko.xz]
# An explicit module path swaps to a locally built module without a full
# colmena deploy (the running system's tools stay at the old version until
# the next deploy - mind the skew).
set -u

FSUUID=de105d4d-df96-444c-8fdb-b616c589a422
SYS=/sys/fs/bcachefs/$FSUUID
POOL_USERS="media-podman utils-podman soundcork nginx-proxy-manager"
SYS_SERVICES="heimdall-sync-watchdog.timer bor.service heimdalld.service bor-snapshot-fetch.service heimdall-snapshot-fetch.service tdarr-node-butthead_worker.service tdarr-server.service nfs-server.service nfs-mountd.service nfs-idmapd.service rpcbind.service rpcbind.socket kopia-maintenance.timer kopia-maintenance.service kopia-register-clients.timer kopia-server.service kopia-register-clients.service"
# NFS-export bind mounts are SIBLINGS of /mnt/user, not children
BIND_MOUNTS="/mnt/Series /mnt/Movies /mnt/downloadtemp"

say()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root (sudo bash $0)"

# NixOS kmod resolves modules against /run/booted-system, so after a no-reboot
# deploy `modinfo`/`modprobe` would still see the OLD module. Locate the module
# inside the freshly deployed system's kernel-modules tree and load from there.
MODULE=${1:-$(find -L /run/current-system/kernel-modules -name 'bcachefs.ko*' 2>/dev/null | head -1)}
[ -n "$MODULE" ] || die "no bcachefs.ko under /run/current-system/kernel-modules - deploy first"

# --- preflight: the module we're swapping to -------------------------------
deployed=$(modinfo "$MODULE" 2>/dev/null | awk '/^version/{print $2; exit}')
[ -n "$deployed" ] || die "modinfo $MODULE has no version"
vermagic=$(modinfo -F vermagic "$MODULE" 2>/dev/null | awk '{print $1}')
running_kver=$(uname -r)
[ "$vermagic" = "$running_kver" ] \
  || die "module vermagic ($vermagic) != running kernel ($running_kver) - aborting before unmount!"
say "swapping to module: $deployed ($MODULE, vermagic $vermagic)"
echo "$deployed" | grep -qE '^1\.[0-9]+\.[0-9]+' \
  || die "unexpected module version '$deployed' - wrong module?"
say "loaded module:      $(cat /sys/module/bcachefs/version 2>/dev/null || echo 'not loaded')"

# Guard against calling umount while flush-bcachefs-* is parked in
# __bch2_wait_on_allocator with Dirty pages: sync_filesystem() inside umount
# would otherwise wedge umount in uninterruptible D state.
for flusher in /proc/[0-9]*/comm; do
  case "$(cat "$flusher" 2>/dev/null)" in
    flush-bcachefs*)
      fpid=${flusher#/proc/}; fpid=${fpid%/comm}
      wchan=$(cat "/proc/$fpid/wchan" 2>/dev/null || true)
      if grep -q 'wait_on_allocator' "/proc/$fpid/stack" 2>/dev/null || [ "$wchan" = "__bch2_wait_on_allocator" ]; then
        dirty_kb=$(awk '/^Dirty:/{print $2}' /proc/meminfo)
        die "PID $fpid ($(cat "$flusher")) is blocked in __bch2_wait_on_allocator (Dirty=${dirty_kb}kB) - drain writeback BEFORE running swap or umount will hang in D state!"
      fi
      ;;
  esac
done

# --- stop everything that uses the pool ------------------------------------
WAS_BOR_ACTIVE=0
systemctl is-active --quiet bor.service 2>/dev/null && WAS_BOR_ACTIVE=1

say "stopping system services: $SYS_SERVICES"
systemctl stop $SYS_SERVICES 2>/dev/null || true
# nfsd is kernel-side: make sure all exports are actually dropped
exportfs -ua 2>/dev/null || true

for u in $POOL_USERS; do
  if id "$u" >/dev/null 2>&1; then
    uid=$(id -u "$u")
    say "stopping user manager: $u (user@$uid.service)"
    systemctl stop "user@$uid.service" 2>/dev/null || true
    loginctl terminate-user "$u" 2>/dev/null || true
  fi
done

find_pool_holders() {
  {
    find /proc/[0-9]*/cwd /proc/[0-9]*/root /proc/[0-9]*/fd -maxdepth 1 \
      \( -lname '/mnt/user*' -o -lname '/mnt/bcachefs*' \
         -o -lname '/mnt/Series*' -o -lname '/mnt/Movies*' \
         -o -lname '/mnt/downloadtemp*' \) \
      -printf '%H %l\n' 2>/dev/null \
      | awk '{
          split($1, a, "/"); pid = a[3];
          if (!seen[pid]++) {
            comm = ""; getline comm < ("/proc/" pid "/comm"); close("/proc/" pid "/comm");
            print pid, comm, $2
          }
        }'
    grep -lE '/mnt/(user|bcachefs|Series|Movies|downloadtemp)' /proc/[0-9]*/maps 2>/dev/null \
      | awk -F/ '{
          pid = $3;
          comm = ""; getline comm < ("/proc/" pid "/comm"); close("/proc/" pid "/comm");
          print pid, comm, "(mmap)"
        }'
  } | sort -u -k1,1n
}

# --- wait for file handles to drain ----------------------------------------
say "waiting for open handles on /mnt/user + /mnt/bcachefs to clear"
holders=""
for i in $(seq 1 30); do
  holders=$(find_pool_holders)
  [ -z "$holders" ] && break
  if [ "$i" = 1 ] || [ $((i % 5)) = 0 ]; then
    say "still open (${i}/30s):"
    echo "$holders" | sed 's/^/    /' | head -20
  fi
  sleep 1
done
if [ -n "$holders" ]; then
  echo "$holders" | head -30
  die "pool still busy after 30s - close/stop the above (e.g. reconcile status / shell cwd) and retry"
fi

# --- unmount ----------------------------------------------------------------
say "unmounting"
for m in $BIND_MOUNTS /mnt/user /mnt/bcachefs; do
  if findmnt -n "$m" >/dev/null 2>&1; then
    umount "$m" || die "umount $m failed"
  fi
done

# --- swap module -------------------------------------------------------------
say "unloading bcachefs module"
modprobe -r bcachefs || die "modprobe -r bcachefs failed (still in use?)"
# deps (lz4/xor/chacha/poly1305) are shared with btrfs and already loaded, but
# `modprobe -r` above removes the ones bcachefs alone was using (lz4hc) -
# reload them or insmod fails with "Unknown symbol LZ4_compress_*".
say "loading new module: $MODULE"
modprobe -a lz4_compress lz4hc_compress raid6_pq xor libchacha libpoly1305 2>/dev/null || true
TMPKO=$(mktemp /tmp/bcachefs.XXXXXX.ko)
xz -dc "$MODULE" > "$TMPKO" 2>/dev/null || cp "$MODULE" "$TMPKO"
insmod "$TMPKO" || die "insmod failed"
rm -f "$TMPKO"
loaded=$(cat /sys/module/bcachefs/version)
srcver=$(cat /sys/module/bcachefs/srcversion 2>/dev/null || echo unknown)
say "loaded module now: $loaded (srcversion $srcver)"
[ "$loaded" = "$deployed" ] || echo "WARNING: expected $deployed, got $loaded"

# --- remount -----------------------------------------------------------------
say "mounting (a scheduled btree_bitmap_gc pass may run once - be patient)"
systemctl start mnt-bcachefs.mount || die "mount /mnt/bcachefs failed"
systemctl start mnt-user.mount    || die "mount /mnt/user failed"
for m in $BIND_MOUNTS; do
  u=$(systemd-escape -p --suffix=mount "$m")
  systemctl start "$u" 2>/dev/null || true
done
findmnt /mnt/bcachefs /mnt/user

# --- kick reconcile ------------------------------------------------------------
say "kicking reconcile pending queue"
echo 1 > "$SYS/internal/trigger_reconcile_pending_wakeup"

# --- restart services ----------------------------------------------------------
say "restarting services"
systemctl start kopia-server.service kopia-register-clients.timer kopia-maintenance.timer nfs-server.service tdarr-server.service tdarr-node-butthead_worker.service heimdalld.service heimdall-sync-watchdog.timer
if [ "$WAS_BOR_ACTIVE" = 1 ]; then
  systemctl start bor.service
fi
for u in $POOL_USERS; do
  uid=$(id -u "$u" 2>/dev/null) && systemctl start "user@$uid"
done

# --- status -------------------------------------------------------------------
say "reconcile status (watch pending + stripes; both should start draining):"
bcachefs reconcile status /mnt/bcachefs || true
say "done. dmesg should NOT be filling with 'watermark: stripe' anymore."
