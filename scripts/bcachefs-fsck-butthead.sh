#!/usr/bin/env bash
# bcachefs-fsck-butthead.sh — run the patched userspace fsck (variant B:
# stripe_needs_reconcile_stale check) on butthead's pool to clear the stale
# needs_reconcile flags. Scoped to check_reconcile_work so it doesn't run
# the full ~1.5h pass set.
#
# Uses -K (userspace fsck) because online/in-kernel fsck would use the
# running UNPATCHED module.
#
# Usage: sudo bash scripts/bcachefs-fsck-butthead.sh [--full]
set -u

BCACHEFS=/nix/store/yk2zcvrlwypvy4xpz4nsnx1655pcka0d-bcachefs-tools-1.39.5/sbin/bcachefs
POOL_USERS="media-podman utils-podman soundcork nginx-proxy-manager"
SYS_SERVICES="tdarr-node-butthead_worker.service tdarr-server.service nfs-server.service nfs-mountd.service nfs-idmapd.service rpcbind.service rpcbind.socket kopia-server.service kopia-register-clients.service"
BIND_MOUNTS="/mnt/Series /mnt/Movies /mnt/downloadtemp"

say()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -x "$BCACHEFS" ] || die "patched tools not found at $BCACHEFS"

FSCK_OPTS=(-K -y)
if [ "${1:-}" != "--full" ]; then
    FSCK_OPTS+=(-o recovery_passes=check_reconcile_work)
fi

SRC=$(findmnt -n -o SOURCE /mnt/bcachefs) || die "/mnt/bcachefs not mounted"
IFS=':' read -ra DEVS <<< "$SRC"
say "members: ${DEVS[*]}"

say "stopping services"
systemctl stop $SYS_SERVICES
exportfs -ua 2>/dev/null || true
for u in $POOL_USERS; do
    id "$u" >/dev/null 2>&1 && loginctl terminate-user "$u"
done

say "waiting for open handles to clear"
for i in $(seq 1 30); do
    holders=$(
        for p in /proc/[0-9]*; do
            for f in "$p"/cwd "$p"/root "$p"/fd/*; do
                r=$(readlink "$f" 2>/dev/null) || continue
                case "$r" in
                    /mnt/user*|/mnt/bcachefs*|/mnt/Series*|/mnt/Movies*|/mnt/downloadtemp*)
                        echo "$p $(cat "$p"/comm 2>/dev/null) $r"; break;;
                esac
            done
        done)
    [ -z "$holders" ] && break
    sleep 1
done
[ -z "$holders" ] || { echo "$holders" | head; die "pool still busy"; }

say "unmounting"
for m in $BIND_MOUNTS /mnt/user /mnt/bcachefs; do
    if findmnt -n "$m" >/dev/null 2>&1; then
        umount "$m" || die "umount $m failed"
    fi
done

say "running patched fsck (${FSCK_OPTS[*]})"
rc=0
"$BCACHEFS" fsck "${FSCK_OPTS[@]}" "${DEVS[@]}" || rc=$?
# fsck exit convention: 0 = clean, 1 = errors found and fixed
[ "$rc" = 0 ] || [ "$rc" = 1 ] || die "fsck failed with exit $rc"
say "fsck done (exit $rc)"

say "remounting"
systemctl start mnt-bcachefs.mount || die "mount /mnt/bcachefs failed"
systemctl start mnt-user.mount    || die "mount /mnt/user failed"
for m in $BIND_MOUNTS; do
    u=$(systemd-escape -p --suffix=mount "$m")
    systemctl start "$u" 2>/dev/null || true
done

say "restarting services"
systemctl start kopia-server.service nfs-server.service tdarr-server.service tdarr-node-butthead_worker.service
for u in $POOL_USERS; do
    uid=$(id -u "$u" 2>/dev/null) && systemctl start "user@$uid"
done

say "done. Check: sudo bcachefs reconcile status /mnt/bcachefs (stripes: should be drained)"
