#!/usr/bin/env python3
"""
kopia-du — Kopia repository space, retention/GC health, and deduplicated
snapshot/directory/file usage analyzer.

Runs via `kopia-admin` by default (on the Kopia server host as root), or via a
custom command specified with --kopia-cmd.
"""

import argparse
import collections
import concurrent.futures
import json
import os
import shlex
import subprocess
import sys
from pathlib import Path


def fmt_bytes(n: float) -> str:
    sign = "-" if n < 0 else ""
    n = abs(float(n))
    for unit in ("B", "KiB", "MiB", "GiB", "TiB", "PiB"):
        if n < 1024.0 or unit == "PiB":
            return f"{sign}{n:6.2f} {unit}" if unit != "B" else f"{sign}{int(n):6d} B  "
        n /= 1024.0
    return f"{sign}{n:.2f} PiB"


def run_cmd(cmd: list[str], check: bool = True) -> str:
    res = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    if check and res.returncode != 0:
        raise RuntimeError(f"Command failed ({res.returncode}): {' '.join(cmd)}\n{res.stderr.strip()}")
    return res.stdout


def dir_disk_bytes(path: str) -> int | None:
    if not path or not os.path.isdir(path):
        return None
    res = subprocess.run(["du", "-sb", path], stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True)
    if res.returncode != 0 or not res.stdout.strip():
        return None
    return int(res.stdout.split()[0])


def detect_repo_path(cfg_path: str) -> str | None:
    try:
        data = json.loads(Path(cfg_path).read_text())
        return data.get("storage", {}).get("config", {}).get("path")
    except Exception:
        return None


def scan_snapshot_tree(kopia_cmd: list[str], root_oid: str) -> list[tuple[str, int, str]]:
    """Return list of (oid, logical_size, rel_path) for all non-directory entries in root_oid."""
    out = run_cmd([*kopia_cmd, "ls", "-lro", "--no-progress", root_oid])
    entries: list[tuple[str, int, str]] = []
    for line in out.splitlines():
        if not line or line[0] == "d":
            continue
        parts = line.split(None, 6)
        if len(parts) < 7:
            continue
        _mode, size_s, _date, _time, _tz, oid, rel_path = parts
        try:
            size = int(size_s)
        except ValueError:
            continue
        entries.append((oid, size, rel_path))
    return entries


def main() -> int:
    ap = argparse.ArgumentParser(description="Analyze Kopia disk space, GC state, and deduplicated file/dir usage.")
    ap.add_argument(
        "--kopia-cmd",
        default="kopia-admin",
        help="Kopia admin wrapper/command (default: 'kopia-admin')",
    )
    ap.add_argument(
        "--repo-config",
        default="/var/lib/kopia/.config/kopia/repository.config",
        help="Path to Kopia repository.config for detecting repoPath on disk",
    )
    ap.add_argument(
        "--source",
        default="",
        help="Optional substring filter on user@host:/path for deep file/dir scan (e.g. 'butthead' or '/var/lib')",
    )
    ap.add_argument(
        "--depth",
        type=int,
        default=2,
        help="Directory rollup depth relative to snapshot root (default: 2, e.g. /var/lib/libvirt/images)",
    )
    ap.add_argument(
        "--top",
        type=int,
        default=25,
        help="Number of top directories/files/snapshots to display (default: 25)",
    )
    ap.add_argument(
        "--max-snapshots",
        type=int,
        default=80,
        help="Max distinct snapshot roots to walk in file/dir scan (0 = skip file scan, -1 = all; default: 80)",
    )
    ap.add_argument(
        "--workers",
        type=int,
        default=6,
        help="Parallel `kopia ls` workers for snapshot tree scan (default: 6)",
    )
    args = ap.parse_args()

    kopia_cmd = shlex.split(args.kopia_cmd)

    print("=" * 88)
    print("1. REPOSITORY DISK USAGE & MAINTENANCE / GC STATUS")
    print("=" * 88)

    repo_path = detect_repo_path(args.repo_config)
    disk_bytes = dir_disk_bytes(repo_path) if repo_path else None
    if repo_path and disk_bytes is not None:
        print(f"Repo path on disk : {repo_path}")
        print(f"Actual disk usage : {fmt_bytes(disk_bytes).strip()} ({disk_bytes:,} bytes)")

    maint_out = run_cmd([*kopia_cmd, "maintenance", "info"], check=False)
    if "snapshot-gc:" not in maint_out:
        print("  [!] WARNING: 'snapshot-gc' has NEVER run on this repository!")
        print("      Expired snapshots NEVER free pack blobs on disk until Full Maintenance runs!")
    print("\n--- kopia maintenance info ---")
    for line in maint_out.strip().splitlines():
        print("  " + line)

    print("\n--- kopia content stats ---")
    stats_out = run_cmd([*kopia_cmd, "content", "stats"], check=False)
    for line in stats_out.strip().splitlines():
        print("  " + line)

    print("\n" + "=" * 88)
    print("2. SPACE BY SOURCE (user@host:/path) — ACTUAL PACKED BYTES & CHURN")
    print("=" * 88)
    print("Computing snapshot storage stats (kopia snapshot list -a -l --storage-stats)...", file=sys.stderr)
    snaps_raw = run_cmd([*kopia_cmd, "snapshot", "list", "-a", "-l", "--storage-stats", "--json", "--no-progress"])
    snaps = json.loads(snaps_raw) if snaps_raw.strip() else []

    if not snaps:
        print("No snapshots found in repository.")
        return 0

    by_source: dict[str, list[dict]] = collections.defaultdict(list)
    for s in snaps:
        src = s.get("source", {})
        label = f"{src.get('userName', '?')}@{src.get('host', '?')}:{src.get('path', '?')}"
        by_source[label].append(s)

    source_rows = []
    snap_deltas = []
    for label, s_list in by_source.items():
        s_list.sort(key=lambda x: x.get("startTime", ""))
        latest = s_list[-1]
        latest_logical = latest.get("rootEntry", {}).get("summ", {}).get("size", 0)
        # runningTotal on the last chronological snapshot of a source reflects cumulative source data;
        # also sum newData.packedContentBytes across all retained snapshots of this source.
        packed_sum_new = 0
        packed_running_max = 0
        for s in s_list:
            st = s.get("storageStats") or {}
            nd = (st.get("newData") or {}).get("packedContentBytes", 0)
            rt = (st.get("runningTotal") or {}).get("packedContentBytes", 0)
            packed_sum_new += nd
            if rt > packed_running_max:
                packed_running_max = rt
            snap_deltas.append((nd, label, s.get("startTime", "")[:19], s.get("rootEntry", {}).get("obj", ""), s.get("retentionReason") or []))
        effective_packed = max(packed_running_max, packed_sum_new)
        source_rows.append((effective_packed, packed_sum_new, latest_logical, len(s_list), label))

    source_rows.sort(reverse=True)
    print(f"{'PACKED TOTAL':>13s}  {'SUM(NEW PACK)':>13s}  {'LATEST LOGICAL':>14s}  {'SNAPS':>5s}  SOURCE")
    print("-" * 88)
    total_latest_logical = 0
    for eff_packed, sum_new, latest_log, count, label in source_rows:
        total_latest_logical += latest_log
        print(f"{fmt_bytes(eff_packed):>13s}  {fmt_bytes(sum_new):>13s}  {fmt_bytes(latest_log):>14s}  {count:5d}  {label}")
    print("-" * 88)
    print(f"{'':>13s}  {'':>13s}  {fmt_bytes(total_latest_logical):>14s}  {len(snaps):5d}  TOTAL ACROSS {len(source_rows)} SOURCES")

    print(f"\n--- Top {min(args.top, len(snap_deltas))} Individual Snapshots Adding Most New Packed Data ---")
    snap_deltas.sort(reverse=True)
    print(f"{'NEW PACKED':>13s}  {'TIMESTAMP':19s}  {'ROOT OID':36s}  SOURCE  [RETENTION]")
    for nd, label, ts, roid, reasons in snap_deltas[: args.top]:
        if nd <= 0:
            break
        r_str = ",".join(reasons[:3])
        print(f"{fmt_bytes(nd):>13s}  {ts:19s}  {roid:36s}  {label}  [{r_str}]")

    if args.max_snapshots == 0:
        return 0

    # Select distinct snapshot roots to scan, prioritizing sources/snapshots with highest newData
    filtered_snaps = [
        s for s in snaps
        if not args.source
        or args.source in f"{s.get('source', {}).get('userName', '')}@{s.get('source', {}).get('host', '')}:{s.get('source', {}).get('path', '')}"
    ]
    # Order snapshots by newData.packedContentBytes descending so if capped by --max-snapshots
    # we always inspect the snapshots holding the most unique data first!
    filtered_snaps.sort(
        key=lambda s: ((s.get("storageStats") or {}).get("newData") or {}).get("packedContentBytes", 0),
        reverse=True,
    )

    roots_to_scan: list[tuple[str, str, str]] = []  # (root_oid, host_source_label, base_path)
    seen_roots: set[str] = set()
    for s in filtered_snaps:
        roid = s.get("rootEntry", {}).get("obj", "")
        if not roid or roid in seen_roots:
            continue
        seen_roots.add(roid)
        src = s.get("source", {})
        src_label = f"{src.get('host', '?')}:{src.get('path', '?')}"
        base_path = src.get("path", "").rstrip("/")
        roots_to_scan.append((roid, src_label, base_path))
        if args.max_snapshots > 0 and len(roots_to_scan) >= args.max_snapshots:
            break

    print("\n" + "=" * 88)
    print(
        f"3. TOP DIRECTORIES & FILES BY DEDUPLICATED LOGICAL SIZE "
        f"(scanning {len(roots_to_scan)}/{len(seen_roots)} distinct snapshot trees)"
    )
    print("   Static files shared across snapshots are counted ONCE; files churning new")
    print("   versions each day sum every distinct object version retained!")
    print("=" * 88)

    seen_file_oids: set[str] = set()
    dir_bytes: dict[str, int] = collections.defaultdict(int)
    file_bytes: dict[str, int] = collections.defaultdict(int)
    file_versions: dict[str, int] = collections.defaultdict(int)

    print(f"Walking {len(roots_to_scan)} snapshot trees with {args.workers} workers...", file=sys.stderr)
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        fut_map = {
            pool.submit(scan_snapshot_tree, kopia_cmd, roid): (roid, src_label, base_path)
            for roid, src_label, base_path in roots_to_scan
        }
        for fut in concurrent.futures.as_completed(fut_map):
            roid, src_label, base_path = fut_map[fut]
            try:
                entries = fut.result()
            except Exception as exc:
                print(f"Warning: failed to ls {roid} ({src_label}): {exc}", file=sys.stderr)
                continue

            host = src_label.split(":", 1)[0]
            for oid, size, rel_path in entries:
                if oid in seen_file_oids:
                    continue
                seen_file_oids.add(oid)

                full_file = f"{host}:{base_path}/{rel_path}"
                file_bytes[full_file] += size
                file_versions[full_file] += 1

                parts = rel_path.split("/")
                # Directory prefix up to args.depth components (excluding filename)
                dir_parts = parts[:-1][: max(1, args.depth)]
                dir_key = f"{host}:{base_path}/" + "/".join(dir_parts) if dir_parts else f"{host}:{base_path}"
                dir_bytes[dir_key] += size

    print(f"\n--- Top {args.top} Directories (depth={args.depth}, deduplicated across snapshots) ---")
    print(f"{'DEDUP LOGICAL':>14s}  HOST:DIRECTORY")
    print("-" * 88)
    for d_key, sz in sorted(dir_bytes.items(), key=lambda kv: kv[1], reverse=True)[: args.top]:
        print(f"{fmt_bytes(sz):>14s}  {d_key}")

    print(f"\n--- Top {args.top} Files (deduplicated; VERS > 1 means daily churn multiplying space!) ---")
    print(f"{'DEDUP LOGICAL':>14s}  {'VERS':>5s}  HOST:FILE")
    print("-" * 88)
    for f_key, sz in sorted(file_bytes.items(), key=lambda kv: kv[1], reverse=True)[: args.top]:
        print(f"{fmt_bytes(sz):>14s}  {file_versions[f_key]:5d}  {f_key}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
