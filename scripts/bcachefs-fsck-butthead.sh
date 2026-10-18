#!/usr/bin/env bash
# bcachefs-fsck-butthead.sh — fsck of butthead's pool, three entry states:
#
#  A) mounted normally      -> stop users, unmount, offline fsck, remount
#  B) not assembled         -> offline fsck, mount
#  C) assembled, no mounts  -> the 2026-10-18 emergency-RO wedge: fs shut
#     down mid-recovery (recovery_status 'Failing: check_alloc_info') and
#     holds the devices exclusively (EBUSY on any fresh mount/fsck).
#     No sysfs disassemble knob exists. NO-REBOOT recovery:
#       1. echo continue > options/errors  (runtime enum; default fix_safe
#          re-trips emergency RO during journal replay, before
#          check_alloc_info can commit its fix -> erofs_trans_commit)
#       2. online fsck (tools attach to the assembled fs; recovery retries
#          the failing pass, now allowed to commit)
#       3. restore errors=fix_safe, mount
#
# Context 2026-10-18: pool went EMERGENCY READ-ONLY at 04:13 during a
# Sonarr import: ec_stripe_create hit "bucket going nonempty but not open"
# (alloc key 5:2912826/sdf1, drifted since the Sept 2 unpatched-1.39.5
# migration era). Files in flight (Series/Always Sunny S08) have extents
# into torn-down stripe creations -> stale_dirty_ptr read errors.
#
# Tools: current-system bcachefs-tools 1.39.6 (carries local patches
# A+C+D+E+F; E = userspace percpu thread-cap for long offline runs).
#
# Default: FULL fsck. --scoped: only recovery_passes=check_reconcile_work.
#
# Usage: sudo bash scripts/bcachefs-fsck-butthead.sh [--scoped]
set -u

BCACHEFS=/run/current-system/sw/bin/bcachefs
FSUUID=de105d4d-df96-444c-8fdb-b616c589a422
SYSFS=/sys/fs/bcachefs/$FSUUID
POOL_USERS="media-podman utils-podman soundcork nginx-proxy-manager"
SYS_SERVICES="tdarr-node-butthead_worker.service tdarr-server.service nfs-server.service nfs-mountd.service nfs-idmapd.service rpcbind.service rpcbind.socket kopia-server.service kopia-register-clients.service"
BIND_MOUNTS="/mnt/Series /mnt/Movies /mnt/downloadtemp"
# Static fallback for state B/C (nothing mounted to derive the list from):
DEVICES_STATIC="/dev/sde1 /dev/sda1 /dev/sdg1 /dev/sdh1 /dev/sdf1 /dev/sdc1 /dev/sdi1 /dev/sdd1 /dev/sdj1 /dev/sdk1"

say()  { echo "==> $*"; }
die()  { echo "ERROR: $*" >&2; exit 1; }

[ "$(id -u)" = 0 ] || die "run as root"
[ -x "$BCACHEFS" ] || die "bcachefs not found at $BCACHEFS"
say "tools: $($BCACHEFS version 2>&1) ($BCACHEFS)"
modinfo bcachefs 2>/dev/null | grep -m1 '^version:' || true

SCOPED=0
[ "${1:-}" = "--scoped" ] && SCOPED=1

stop_users() {
    say "stopping services"
    systemctl stop kopia-register-clients.timer 2>/dev/null || true
    systemctl stop $SYS_SERVICES
    exportfs -ua 2>/dev/null || true
    for u in $POOL_USERS; do
        id "$u" >/dev/null 2>&1 && loginctl terminate-user "$u"
    done
}

wait_handles() {
    say "waiting for open handles to clear"
    local i holders
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
}

do_mounts() {
    say "mounting"
    systemctl start mnt-bcachefs.mount || die "mount /mnt/bcachefs failed"
    systemctl start mnt-user.mount    || die "mount /mnt/user failed"
    for m in $BIND_MOUNTS; do
        u=$(systemd-escape -p --suffix=mount "$m")
        systemctl start "$u" 2>/dev/null || true
    done
}

restart_services() {
    say "restarting services"
    systemctl start kopia-server.service nfs-server.service tdarr-server.service tdarr-node-butthead_worker.service
    for u in $POOL_USERS; do
        uid=$(id -u "$u" 2>/dev/null) && systemctl start "user@$uid"
    done
}

run_fsck() { # run_fsck <mode:offline|online> <devices...>
    local mode=$1; shift
    local opts=(-y)
    [ "$mode" = offline ] && opts=(-K -y -o fix_errors)
    [ "$SCOPED" = 1 ] && opts+=(-o recovery_passes=check_reconcile_work)
    say "running $mode fsck (${opts[*]}) on: $*"
    local rc=0
    "$BCACHEFS" fsck "${opts[@]}" "$@" || rc=$?
    # fsck exit convention: 0 = clean, 1 = errors found and fixed
    [ "$rc" = 0 ] || [ "$rc" = 1 ] || die "fsck failed with exit $rc"
    say "fsck done (exit $rc)"
}

# --- state detection -----------------------------------------------------
if findmnt -n /mnt/bcachefs >/dev/null 2>&1; then
    STATE=A
    SRC=$(findmnt -n -o SOURCE /mnt/bcachefs)
    IFS=':' read -ra DEVS <<< "$SRC"
elif [ -d "$SYSFS" ]; then
    STATE=C
    read -ra DEVS <<< "$DEVICES_STATIC"
else
    STATE=B
    read -ra DEVS <<< "$DEVICES_STATIC"
fi
say "state $STATE; members: ${DEVS[*]}"

# --- state C: wedged assembly, online recovery ---------------------------
if [ "$STATE" = C ]; then
    say "fs assembled without mounts (emergency-RO wedge) - online recovery"
    [ -w "$SYSFS/options/errors" ] || die "$SYSFS/options/errors not writable"
    cur=$(cat "$SYSFS/options/errors")
    case "$cur" in *"[continue]"*) : ;; *) echo continue > "$SYSFS/options/errors" || die "failed to set errors=continue";; esac
    cat "$SYSFS/options/errors"
    stop_users   # belt & braces; nothing should be using the pool anyway
    run_fsck online "${DEVS[@]}"
    echo fix_safe > "$SYSFS/options/errors" || true
    do_mounts
    restart_services
    say "done. Verify Always Sunny S08 reads; check $SYSFS/errors"
    exit 0
fi

# --- states A/B: offline fsck --------------------------------------------
if [ "$STATE" = A ]; then
    stop_users
    wait_handles
    say "unmounting"
    for m in $BIND_MOUNTS /mnt/user /mnt/bcachefs; do
        if findmnt -n "$m" >/dev/null 2>&1; then
            umount "$m" || die "umount $m failed"
        fi
    done
else
    stop_users
fi

# after unmount, the assembly must be fully gone or offline fsck gets EBUSY
if [ -d "$SYSFS" ]; then
    die "fs still assembled after unmount (wedged) - rerun this script to take the state-C online path"
fi

if [ "$SCOPED" = 1 ]; then
    say "SCOPED fsck: check_reconcile_work only"
else
    say "FULL fsck (expect ~1.5h+; 32T used on 10 devices)"
fi
run_fsck offline "${DEVS[@]}"
do_mounts
restart_services

say "done. Verify:"
echo "  - read test the Always Sunny S08 files (E02/E06 were unreadable, E08 was mid-copy)"
echo "  - re-import/re-grab whatever is still broken"
echo "  - sudo bcachefs reconcile status /mnt/bcachefs"
echo "  - cat $SYSFS/errors"
