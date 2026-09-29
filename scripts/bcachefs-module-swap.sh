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
SYS_SERVICES="tdarr-node-butthead_worker.service tdarr-server.service nfs-server.service nfs-mountd.service nfs-idmapd.service rpcbind.service rpcbind.socket kopia-server.service kopia-register-clients.service"
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
say "swapping to module: $deployed ($MODULE)"
echo "$deployed" | grep -q '^1\.39\.6$' \
  || die "module is $deployed, expected 1.39.6 - wrong module?"
say "loaded module:      $(cat /sys/module/bcachefs/version 2>/dev/null || echo 'not loaded')"

# --- stop everything that uses the pool ------------------------------------
say "stopping system services: $SYS_SERVICES"
systemctl stop $SYS_SERVICES
# nfsd is kernel-side: make sure all exports are actually dropped
exportfs -ua 2>/dev/null || true

for u in $POOL_USERS; do
  if id "$u" >/dev/null 2>&1; then
    say "terminating user manager: $u"
    loginctl terminate-user "$u"
  fi
done

# --- wait for file handles to drain ----------------------------------------
say "waiting for open handles on /mnt/user + /mnt/bcachefs to clear"
for i in $(seq 1 30); do
  holders=$(
    for p in /proc/[0-9]*; do
      for f in "$p"/cwd "$p"/root "$p"/fd/*; do
        r=$(readlink "$f" 2>/dev/null) || continue
        case "$r" in
          /mnt/user*|/mnt/bcachefs*|/mnt/Series*|/mnt/Movies*|/mnt/downloadtemp*) echo "$p $(cat "$p"/comm 2>/dev/null) $r"; break;;
        esac
      done
    done)
  [ -z "$holders" ] && break
  sleep 1
done
if [ -n "$holders" ]; then
  echo "$holders" | head -20
  die "pool still busy after 30s - stop the above and retry"
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
modprobe lz4_compress lz4hc_compress xor libchacha libpoly1305 2>/dev/null || true
TMPKO=$(mktemp /tmp/bcachefs.XXXXXX.ko)
xz -dc "$MODULE" > "$TMPKO" 2>/dev/null || cp "$MODULE" "$TMPKO"
insmod "$TMPKO" || die "insmod failed"
rm -f "$TMPKO"
loaded=$(cat /sys/module/bcachefs/version)
say "loaded module now: $loaded"
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
systemctl start kopia-server.service nfs-server.service tdarr-server.service tdarr-node-butthead_worker.service
for u in $POOL_USERS; do
  uid=$(id -u "$u" 2>/dev/null) && systemctl start "user@$uid"
done

# --- status -------------------------------------------------------------------
say "reconcile status (watch pending + stripes; both should start draining):"
bcachefs reconcile status /mnt/bcachefs || true
say "done. dmesg should NOT be filling with 'watermark: stripe' anymore."
