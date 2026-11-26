{ ... }: {
  flake.modules.homeManager.yolo-agents =
{
  config,
  pkgs,
  lib,
  hostname ? "",
  ...
}:
let
  vmWriteUrl = "http://hierro.netbird.cloud:8428/write";
  vmQueryUrl = "http://hierro.netbird.cloud:8428/api/v1/query";

  bwrapYolo = pkgs.writeShellScriptBin "bwrap-yolo" ''
    set -euo pipefail

    workdir=$(pwd -P)
    extra_binds=()
    cmd_args=()

    while [ $# -gt 0 ]; do
      case "$1" in
        --)
          shift
          cmd_args+=("$@")
          break
          ;;
        --ro)
          if [ $# -lt 2 ]; then
            echo "bwrap-yolo: --ro requires a path" >&2
            exit 1
          fi
          p=$(realpath -s -m -- "$2")
          extra_binds+=(--ro-bind "$p" "$p")
          shift 2
          ;;
        --ro=*)
          p=$(realpath -s -m -- "''${1#--ro=}")
          extra_binds+=(--ro-bind "$p" "$p")
          shift
          ;;
        --rw)
          if [ $# -lt 2 ]; then
            echo "bwrap-yolo: --rw requires a path" >&2
            exit 1
          fi
          p=$(realpath -s -m -- "$2")
          extra_binds+=(--bind "$p" "$p")
          shift 2
          ;;
        --rw=*)
          p=$(realpath -s -m -- "''${1#--rw=}")
          extra_binds+=(--bind "$p" "$p")
          shift
          ;;
        *)
          cmd_args+=("$@")
          break
          ;;
      esac
    done

    if [ "''${#cmd_args[@]}" -eq 0 ]; then
      echo "Usage: bwrap-yolo [--ro <dir>]... [--rw <dir>]... [--] <command> [args...]" >&2
      exit 1
    fi

    if [ "$(uname -s)" != "Linux" ]; then
      exec "''${cmd_args[@]}"
    fi

    state_base="''${XDG_STATE_HOME:-$HOME/.local/state}/yolo-agents"
    mkdir -p \
      "$HOME/.kimi" \
      "$HOME/.config/opencode" \
      "$HOME/.local/share/opencode" \
      "$HOME/.pi" \
      "$HOME/.claude" \
      "$HOME/.gemini" \
      "$HOME/.codex" \
      "$state_base"

    # Expose only the specific LLM provider API key targets referenced by
    # opencode/pi symlinks without exposing other sops secrets (~/.git-credentials, ssh, etc.).
    secret_binds=()
    for keyname in openrouter-api-key opencodego-api-key zai-api-key; do
      for candidate in "$HOME/.local/share/opencode/$keyname" "$HOME/.config/sops-nix/secrets/$keyname"; do
        if [ -e "$candidate" ]; then
          real_secret=$(realpath "$candidate" 2>/dev/null || true)
          if [ -n "$real_secret" ] && [ -r "$real_secret" ]; then
            secret_binds+=(--ro-bind-try "$real_secret" "$HOME/.config/sops-nix/secrets/$keyname")
            if [ "$real_secret" != "$HOME/.config/sops-nix/secrets/$keyname" ]; then
              secret_binds+=(--ro-bind-try "$real_secret" "$real_secret")
            fi
          fi
        fi
      done
    done

    bwrap_args=(
      # 1. Isolate mount, user, IPC, UTS, and cgroup namespaces; keep PID & network shared
      --unshare-user
      --unshare-ipc
      --unshare-uts
      --unshare-cgroup-try
      --die-with-parent
      # 2. Core virtual filesystems
      --ro-bind /proc /proc
      --ro-bind-try /sys /sys
      --dev /dev
      --tmpfs /tmp
      --tmpfs /run
      # 3. Read-only system binaries, libraries, and Nix store
      --ro-bind /usr /usr
      --ro-bind-try /bin /bin
      --ro-bind-try /lib /lib
      --ro-bind-try /lib64 /lib64
      --ro-bind-try /nix /nix
      --ro-bind-try /run/current-system /run/current-system
      # 4. Network & TLS requirements
      --ro-bind /etc/resolv.conf /etc/resolv.conf
      --ro-bind-try /etc/hosts /etc/hosts
      --ro-bind-try /etc/nsswitch.conf /etc/nsswitch.conf
      --ro-bind-try /etc/ssl /etc/ssl
      --ro-bind-try /etc/ca-certificates /etc/ca-certificates
      --ro-bind-try /etc/pki /etc/pki
      --ro-bind-try /etc/static /etc/static
      --ro-bind-try /opt /opt
      --ro-bind-try /etc/profiles /etc/profiles
      # 5. Mask $HOME with tmpfs so ~/.ssh, ~/.aws, etc. are invisible
      --tmpfs "$HOME"
      # 6. Re-bind only agent state/auth, yolo state/hooks, & read-only gitconfig
      --ro-bind-try "$HOME/.gitconfig" "$HOME/.gitconfig"
      --ro-bind-try "$HOME/.local/bin" "$HOME/.local/bin"
      --bind-try "$state_base" "$state_base"
      --bind-try "$HOME/.kimi" "$HOME/.kimi"
      --bind-try "$HOME/.config/opencode" "$HOME/.config/opencode"
      --bind-try "$HOME/.local/share/opencode" "$HOME/.local/share/opencode"
      --bind-try "$HOME/.pi" "$HOME/.pi"
      --bind-try "$HOME/.claude" "$HOME/.claude"
      --ro-bind-try "$HOME/.claude.json" "$HOME/.claude.json"
      --ro-bind-try "$HOME/.toolbox" "$HOME/.toolbox"
      --ro-bind-try "$HOME/.opencode" "$HOME/.opencode"
      --ro-bind-try "$HOME/.kilo" "$HOME/.kilo"
      --ro-bind-try "$HOME/dev" "$HOME/dev"
      --bind-try "$HOME/workspace" "$HOME/workspace"
      --bind-try /Volumes/workplace /Volumes/workplace
      --bind-try "$HOME/.gemini" "$HOME/.gemini"
      --bind-try "$HOME/.codex" "$HOME/.codex"
      "''${secret_binds[@]}"
      # 7. Mount ONLY current project directory RW (with .git/hooks & .git/config protected)
      --bind "$workdir" "$workdir"
      --ro-bind-try "$workdir/.git/hooks" "$workdir/.git/hooks"
      --ro-bind-try "$workdir/.git/config" "$workdir/.git/config"
      # 8. Extra user-specified RO/RW mounts
      "''${extra_binds[@]}"
      --chdir "$workdir"
    )

    exec bwrap "''${bwrap_args[@]}" -- "''${cmd_args[@]}"
  '';

  yoloRunner = pkgs.writeScriptBin "yolo-agent-runner" ''
    #!${pkgs.python3}/bin/python3
    import fcntl
    import hashlib
    import json
    import os
    import pathlib
    import re
    import shutil
    import signal
    import socket
    import sqlite3
    import subprocess
    import sys
    import threading
    import time
    import uuid

    AGENTS_WITH_ADD_DIR = {"claude", "agy", "kimi", "codex"}

    def ensure_user_path() -> None:
        home = os.path.expanduser("~")
        user = os.environ.get("USER") or pathlib.Path(home).name
        prepend = [
            f"{home}/bin",
            f"{home}/.cargo/bin",
            f"{home}/.toolbox/bin",
            f"{home}/.opencode/bin",
            f"{home}/.kilo/bin",
            f"{home}/.local/bin",
        ]
        append = [
            f"/etc/profiles/per-user/{user}/bin",
            f"{home}/.nix-profile/bin",
            "/run/current-system/sw/bin",
        ]
        cur = [p for p in os.environ.get("PATH", "").split(":") if p]
        out = []
        for p in prepend + cur + append:
            if p not in out and os.path.isdir(p):
                out.append(p)
        os.environ["PATH"] = ":".join(out)

    def state_root() -> pathlib.Path:
        base = os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")
        p = pathlib.Path(base) / "yolo-agents"
        (p / "locks").mkdir(parents=True, exist_ok=True)
        (p / "sessions").mkdir(parents=True, exist_ok=True)
        return p

    def sanitize_slug(name: str) -> str:
        s = re.sub(r"[^A-Za-z0-9._-]+", "-", name).strip("-")
        return s or "workspace"

    def workdir_key(workdir: str) -> str:
        h = hashlib.sha1(workdir.encode("utf-8")).hexdigest()[:10]
        base = sanitize_slug(os.path.basename(workdir) or "root")
        return f"{base}-{h}"

    def is_slot_locked(locks_dir: pathlib.Path, slot: str) -> bool:
        lock_path = locks_dir / f"{slot}.lock"
        if not lock_path.exists():
            return False
        fd = os.open(str(lock_path), os.O_RDWR | os.O_CREAT, 0o600)
        try:
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError:
                return True
            else:
                fcntl.flock(fd, fcntl.LOCK_UN)
                return False
        finally:
            os.close(fd)

    def existing_zellij_sessions() -> set[str]:
        if not shutil.which("zellij"):
            return set()
        try:
            res = subprocess.run(
                ["zellij", "list-sessions", "--no-formatting", "--short"],
                capture_output=True,
                text=True,
                timeout=3,
            )
            if res.returncode == 0:
                return {line.strip() for line in res.stdout.splitlines() if line.strip()}
        except Exception:
            pass
        return set()

    def allocate_slot(workdir: str, check_zellij_names: bool) -> str:
        base = sanitize_slug(os.path.basename(workdir) or "root")
        locks_dir = state_root() / "locks"
        z_sessions = existing_zellij_sessions() if check_zellij_names else set()
        n = 1
        while True:
            cand = f"{base}-{n}"
            if not is_slot_locked(locks_dir, cand) and cand not in z_sessions:
                return cand
            n += 1

    def atomic_write_json(path: pathlib.Path, data: dict) -> None:
        tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
        tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, path)

    def load_json(path: pathlib.Path) -> dict:
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except Exception:
            return {}

    def claude_transcript_exists(session_uuid: str) -> bool:
        projects = pathlib.Path(os.path.expanduser("~/.claude/projects"))
        if not projects.is_dir():
            return False
        target = f"{session_uuid}.jsonl"
        for _root, _dirs, files in os.walk(projects):
            if target in files:
                return True
        return False

    def claimed_ids(sessions_dir: pathlib.Path, field: str, exclude_path: pathlib.Path) -> set[str]:
        out = set()
        for p in sessions_dir.glob("*.json"):
            if p.resolve() == exclude_path.resolve():
                continue
            val = load_json(p).get(field)
            if val:
                out.add(val)
        return out

    def start_opencode_watcher(workdir: str, launch_ms: int, state_path: pathlib.Path, stop_evt: threading.Event) -> None:
        db_path = pathlib.Path(os.path.expanduser("~/.local/share/opencode/opencode.db"))
        sessions_dir = state_path.parent

        def _watch() -> None:
            deadline = time.monotonic() + 300.0
            while not stop_evt.is_set() and time.monotonic() < deadline:
                if db_path.is_file():
                    try:
                        taken = claimed_ids(sessions_dir, "opencode_session_id", state_path)
                        uri = f"file:{db_path}?mode=ro"
                        con = sqlite3.connect(uri, uri=True, timeout=2.0)
                        try:
                            rows = con.execute(
                                "SELECT id FROM session_v2 WHERE directory = ? AND time_created >= ? ORDER BY time_created ASC",
                                (workdir, launch_ms - 5000),
                            ).fetchall()
                        finally:
                            con.close()
                        for (sid,) in rows:
                            if sid and sid not in taken:
                                st = load_json(state_path)
                                st["opencode_session_id"] = sid
                                atomic_write_json(state_path, st)
                                return
                    except Exception:
                        pass
                stop_evt.wait(2.0)

        t = threading.Thread(target=_watch, daemon=True)
        t.start()

    def start_agy_watcher(before_ids: set[str], state_path: pathlib.Path, stop_evt: threading.Event) -> None:
        brain_dir = pathlib.Path(os.path.expanduser("~/.gemini/antigravity-cli/brain"))
        sessions_dir = state_path.parent
        uuid_re = re.compile(r"^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$")

        def _watch() -> None:
            deadline = time.monotonic() + 300.0
            while not stop_evt.is_set() and time.monotonic() < deadline:
                # statusline.sh also updates state_path directly (including on /fork);
                # stop polling once an ID is recorded.
                if load_json(state_path).get("agy_conversation_id"):
                    return
                if brain_dir.is_dir():
                    try:
                        taken = claimed_ids(sessions_dir, "agy_conversation_id", state_path)
                        candidates = []
                        for entry in brain_dir.iterdir():
                            if entry.is_dir() and uuid_re.match(entry.name):
                                if entry.name not in before_ids and entry.name not in taken:
                                    candidates.append((entry.stat().st_mtime, entry.name))
                        if candidates:
                            candidates.sort()
                            cid = candidates[0][1]
                            st = load_json(state_path)
                            st.setdefault("agy_conversation_id", cid)
                            atomic_write_json(state_path, st)
                            return
                    except Exception:
                        pass
                stop_evt.wait(2.0)

        t = threading.Thread(target=_watch, daemon=True)
        t.start()

    def start_codex_watcher(before_files: set[str], state_path: pathlib.Path, stop_evt: threading.Event) -> None:
        codex_dir = pathlib.Path(os.path.expanduser("~/.codex/sessions"))
        sessions_dir = state_path.parent
        uuid_re = re.compile(r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})")

        def _watch() -> None:
            deadline = time.monotonic() + 300.0
            while not stop_evt.is_set() and time.monotonic() < deadline:
                if codex_dir.is_dir():
                    try:
                        taken = claimed_ids(sessions_dir, "codex_session_id", state_path)
                        for root, _dirs, files in os.walk(codex_dir):
                            for fn in files:
                                full = os.path.join(root, fn)
                                if fn.endswith(".jsonl") and full not in before_files:
                                    m = uuid_re.search(fn)
                                    if m and m.group(1) not in taken:
                                        st = load_json(state_path)
                                        st["codex_session_id"] = m.group(1)
                                        atomic_write_json(state_path, st)
                                        return
                    except Exception:
                        pass
                stop_evt.wait(2.0)

        t = threading.Thread(target=_watch, daemon=True)
        t.start()

    def build_agent_invocation(agent: str, slot: str, workdir: str, state_path: pathlib.Path, fresh: bool, extra_dirs: list[str], agent_args: list[str], stop_evt: threading.Event) -> list[str]:
        state = load_json(state_path)
        if not state.get("session_uuid"):
            state["session_uuid"] = str(uuid.uuid4())
            atomic_write_json(state_path, state)
        sid = state["session_uuid"]

        dir_flags: list[str] = []
        if agent in AGENTS_WITH_ADD_DIR:
            for d in extra_dirs:
                if os.path.isdir(d):
                    dir_flags.extend(["--add-dir", d])

        if agent == "claude":
            cmd = ["claude", "--dangerously-skip-permissions", "--settings", '{"sandbox":{"enabled":false}}']
            has_session_flag = any(
                a in ("-c", "--continue", "-r", "--resume", "--session-id")
                or a.startswith("--resume=")
                or a.startswith("--session-id=")
                for a in agent_args
            )
            has_name_flag = any(a in ("-n", "--name") or a.startswith("--name=") for a in agent_args)
            if not has_session_flag:
                if not fresh and claude_transcript_exists(sid):
                    cmd.extend(["--resume", sid])
                else:
                    cmd.extend(["--session-id", sid])
            if not has_name_flag:
                cmd.extend(["-n", slot])
            return cmd + dir_flags + agent_args

        if agent == "pi":
            cmd = ["pi"]
            has_session_flag = any(
                a in ("-c", "--continue", "-r", "--resume", "--session", "--no-session")
                or a.startswith("--session=")
                for a in agent_args
            )
            if not has_session_flag:
                pi_sessions = pathlib.Path(os.path.expanduser("~/.pi/yolo-sessions"))
                pi_sessions.mkdir(parents=True, exist_ok=True)
                pi_file = pi_sessions / f"{workdir_key(workdir)}__{slot}.jsonl"
                if fresh and pi_file.exists():
                    try:
                        pi_file.unlink()
                    except OSError:
                        pass
                cmd.extend(["--session", str(pi_file)])
            return cmd + agent_args

        if agent == "kimi":
            cmd = ["kimi", "--yolo"]
            has_session_flag = any(
                a in ("--continue", "--session", "--resume")
                or a.startswith("--session=")
                or a.startswith("--resume=")
                for a in agent_args
            )
            if not has_session_flag:
                cmd.extend(["--session", sid])
            return cmd + dir_flags + agent_args

        if agent == "opencode":
            cmd = ["opencode", "--auto"]
            has_session_flag = any(
                a in ("-c", "--continue", "-s", "--session")
                or a.startswith("--session=")
                for a in agent_args
            )
            if not has_session_flag:
                if not fresh:
                    oc_id = state.get("opencode_session_id")
                    if oc_id:
                        cmd.extend(["-s", oc_id])
                    else:
                        cmd.append("--continue")
                else:
                    start_opencode_watcher(workdir, int(time.time() * 1000), state_path, stop_evt)
            return cmd + agent_args

        if agent == "agy":
            cmd = ["agy", "--dangerously-skip-permissions"]
            has_session_flag = any(
                a in ("-c", "--continue", "--conversation")
                or a.startswith("--conversation=")
                for a in agent_args
            )
            if not has_session_flag:
                brain_dir = pathlib.Path(os.path.expanduser("~/.gemini/antigravity-cli/brain"))
                if not fresh:
                    cid = state.get("agy_conversation_id")
                    if cid and (brain_dir / cid).is_dir():
                        cmd.extend(["--conversation", cid])
                    else:
                        cmd.append("--continue")
                else:
                    before = {e.name for e in brain_dir.iterdir() if e.is_dir()} if brain_dir.is_dir() else set()
                    start_agy_watcher(before, state_path, stop_evt)
            return cmd + dir_flags + agent_args

        if agent == "codex":
            cmd = ["codex", "--dangerously-bypass-approvals-and-sandbox"] + dir_flags
            has_resume = "resume" in agent_args
            if not has_resume:
                codex_dir = pathlib.Path(os.path.expanduser("~/.codex/sessions"))
                if not fresh:
                    cid = state.get("codex_session_id")
                    if cid:
                        return cmd + agent_args + ["resume", cid]
                    return cmd + agent_args + ["resume", "--last"]
                else:
                    before_files: set[str] = set()
                    if codex_dir.is_dir():
                        for r, _d, fs in os.walk(codex_dir):
                            for fn in fs:
                                if fn.endswith(".jsonl"):
                                    before_files.add(os.path.join(r, fn))
                    start_codex_watcher(before_files, state_path, stop_evt)
            return cmd + agent_args

        raise SystemExit(f"yolo-agent-runner: unknown agent '{agent}'")

    def main() -> int:
        ensure_user_path()
        if len(sys.argv) < 2:
            print("Usage: yolo-agent-runner <agent> [options] [-- <agent-args>...]", file=sys.stderr)
            return 1

        agent = sys.argv[1]
        raw_argv = sys.argv[2:]

        slot: str | None = None
        resurrect = False
        in_command_pane = False
        no_zellij = False

        bwrap_flags: list[str] = []
        extra_dirs: list[str] = []
        agent_args: list[str] = []

        i = 0
        while i < len(raw_argv):
            arg = raw_argv[i]
            if arg == "--":
                agent_args.extend(raw_argv[i + 1 :])
                break
            elif arg in ("--slot", "-S") and i + 1 < len(raw_argv):
                slot = sanitize_slug(raw_argv[i + 1])
                i += 2
                continue
            elif arg.startswith("--slot="):
                slot = sanitize_slug(arg.split("=", 1)[1])
                i += 1
                continue
            elif arg == "--resurrect":
                resurrect = True
                i += 1
                continue
            elif arg == "--in-command-pane":
                in_command_pane = True
                i += 1
                continue
            elif arg == "--no-zellij":
                no_zellij = True
                i += 1
                continue
            elif arg in ("--ro", "--rw"):
                if i + 1 >= len(raw_argv):
                    print(f"yolo-{agent}: {arg} requires a path", file=sys.stderr)
                    return 1
                p = os.path.abspath(os.path.expanduser(raw_argv[i + 1]))
                bwrap_flags.extend([arg, p])
                extra_dirs.append(p)
                i += 2
                continue
            elif arg.startswith("--ro=") or arg.startswith("--rw="):
                flag, val = arg.split("=", 1)
                p = os.path.abspath(os.path.expanduser(val))
                bwrap_flags.extend([flag, p])
                extra_dirs.append(p)
                i += 1
                continue
            else:
                agent_args.append(arg)
                i += 1

        workdir = os.path.realpath(os.getcwd())
        root = state_root()
        in_zellij = bool(os.environ.get("ZELLIJ"))
        has_zellij = bool(shutil.which("zellij"))

        if slot is None:
            check_z = (not in_zellij) and (not no_zellij) and has_zellij
            slot = allocate_slot(workdir, check_zellij_names=check_z)

        state_path = root / "sessions" / f"{workdir_key(workdir)}__{slot}.json"

        # Stage 1: Not yet inside a dedicated Zellij command pane -> wrap in Zellij!
        if not in_command_pane and not no_zellij and has_zellij:
            if not resurrect:
                atomic_write_json(
                    state_path,
                    {
                        "slot": slot,
                        "agent": agent,
                        "workdir": workdir,
                        "session_uuid": str(uuid.uuid4()),
                        "needs_fresh_start": True,
                        "created_at": int(time.time()),
                    },
                )

            inner_cmd = [f"yolo-{agent}", "--in-command-pane", "--slot", slot, "--resurrect"] + bwrap_flags
            if agent_args:
                inner_cmd.extend(["--"] + agent_args)

            if not in_zellij:
                os.execvp(
                    "zellij",
                    ["zellij", "attach", "--create", "--force-run-commands", slot, "--"] + inner_cmd,
                )
            else:
                res = subprocess.run(
                    ["zellij", "run", "--in-place", "--cwd", workdir, "-n", f"{slot} ({agent})", "--"] + inner_cmd
                )
                return res.returncode

        # Stage 2: Inside the command pane (or --no-zellij) -> lock slot, tag pane, launch bwrap-yolo!
        locks_dir = root / "locks"
        lock_file = locks_dir / f"{slot}.lock"
        meta_file = locks_dir / f"{slot}.json"
        lock_fd = os.open(str(lock_file), os.O_RDWR | os.O_CREAT, 0o600)
        got_lock = False
        try:
            fcntl.flock(lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            got_lock = True
        except BlockingIOError:
            pass

        if in_zellij and has_zellij:
            try:
                subprocess.run(
                    ["zellij", "action", "rename-pane", f"{slot} ({agent})"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=2,
                )
            except Exception:
                pass

        state = load_json(state_path) if resurrect else {}
        if not state:
            state = {
                "slot": slot,
                "agent": agent,
                "workdir": workdir,
                "session_uuid": str(uuid.uuid4()),
                "needs_fresh_start": not resurrect,
                "created_at": int(time.time()),
            }

        fresh = bool(state.get("needs_fresh_start", not resurrect))
        state["needs_fresh_start"] = False
        state["last_started_at"] = int(time.time())
        atomic_write_json(state_path, state)

        host_name = os.environ.get("YOLO_HOST") or "${hostname}" or socket.gethostname().split(".")[0]

        if got_lock:
            atomic_write_json(
                meta_file,
                {
                    "slot": slot,
                    "agent": agent,
                    "pid": os.getpid(),
                    "workdir": workdir,
                    "zellij_session": os.environ.get("ZELLIJ_SESSION_NAME", ""),
                    "started_at": int(time.time()),
                },
            )

        stop_evt = threading.Event()
        agent_cmd = build_agent_invocation(
            agent=agent,
            slot=slot,
            workdir=workdir,
            state_path=state_path,
            fresh=fresh,
            extra_dirs=extra_dirs,
            agent_args=agent_args,
            stop_evt=stop_evt,
        )

        child_env = dict(os.environ)
        child_env["YOLO_SLOT"] = slot
        child_env["YOLO_STATE_FILE"] = str(state_path)
        child_env["YOLO_HOST"] = host_name

        full_cmd = ["bwrap-yolo"] + bwrap_flags + ["--"] + agent_cmd
        proc = subprocess.Popen(full_cmd, env=child_env)

        def _forward_sig(signum, _frame):
            if proc.poll() is None:
                try:
                    proc.send_signal(signum)
                except ProcessLookupError:
                    pass

        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            signal.signal(sig, _forward_sig)

        try:
            return proc.wait()
        finally:
            stop_evt.set()
            if got_lock:
                try:
                    meta_file.unlink(missing_ok=True)
                except OSError:
                    pass
                try:
                    fcntl.flock(lock_fd, fcntl.LOCK_UN)
                except OSError:
                    pass
            os.close(lock_fd)

    if __name__ == "__main__":
        sys.exit(main())
  '';

  mkYoloWrapper = agent:
    pkgs.writeShellScriptBin "yolo-${agent}" ''
      exec ${yoloRunner}/bin/yolo-agent-runner ${lib.escapeShellArg agent} "$@"
    '';

  # Resurrect helper for bare (non-yolo) `agy` panes: uses the exact conversation_id
  # pinned by statusline.sh for this Zellij pane / CWD, or falls back to `agy --continue`.
  agyResurrect = pkgs.writeScriptBin "agy-resurrect" ''
    #!${pkgs.python3}/bin/python3
    import hashlib
    import os
    import pathlib
    import sys

    base = pathlib.Path(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")) / "yolo-agents"
    brain = pathlib.Path(os.path.expanduser("~/.gemini/antigravity-cli/brain"))
    cwd = os.path.realpath(os.getcwd())

    candidates = []
    zs = os.environ.get("ZELLIJ_SESSION_NAME", "")
    zp = os.environ.get("ZELLIJ_PANE_ID", "")
    if zs and zp:
        candidates.append(base / "agy-panes" / f"{zs}__{zp}.id")
    cwd_hash = hashlib.sha1(cwd.encode("utf-8")).hexdigest()[:12]
    candidates.append(base / "agy-cwds" / f"{cwd_hash}.id")

    for p in candidates:
        if p.is_file():
            cid = p.read_text(encoding="utf-8").strip()
            if cid and (brain / cid).is_dir():
                os.execvp("agy", ["agy", f"--conversation={cid}"] + sys.argv[1:])

    os.execvp("agy", ["agy", "--continue"] + sys.argv[1:])
  '';

  yoloLs = pkgs.writeScriptBin "yolo-ls" ''
    #!${pkgs.python3}/bin/python3
    import datetime as dt
    import fcntl
    import json
    import os
    import pathlib
    import shutil
    import subprocess
    import sys
    import time
    import urllib.parse
    import urllib.request

    fleet_mode = "--fleet" in sys.argv or "-f" in sys.argv
    base = pathlib.Path(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")) / "yolo-agents"
    locks_dir = base / "locks"
    agy_dir = base / "agy"

    live = []
    if locks_dir.is_dir():
        for lf in sorted(locks_dir.glob("*.lock")):
            slot = lf.stem
            fd = os.open(str(lf), os.O_RDWR)
            try:
                try:
                    fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                except BlockingIOError:
                    meta_path = locks_dir / f"{slot}.json"
                    meta = {}
                    if meta_path.is_file():
                        try:
                            meta = json.loads(meta_path.read_text(encoding="utf-8"))
                        except Exception:
                            pass
                    live.append((slot, meta))
                else:
                    fcntl.flock(fd, fcntl.LOCK_UN)
            finally:
                os.close(fd)

    # Index local agy live telemetry by slot
    agy_by_slot = {}
    if agy_dir.is_dir():
        for af in agy_dir.glob("*.json"):
            try:
                d = json.loads(af.read_text(encoding="utf-8"))
                sl = d.get("slot")
                if sl:
                    prev = agy_by_slot.get(sl)
                    if not prev or d.get("updated_at", 0) >= prev.get("updated_at", 0):
                        agy_by_slot[sl] = d
            except Exception:
                pass

    print("=== Local Running YOLO Agents ===")
    if not live:
        print("  (none)")
    else:
        now = int(time.time())
        for slot, m in live:
            ts = m.get("started_at")
            since = dt.datetime.fromtimestamp(ts).strftime("%H:%M:%S") if ts else "?"
            z = m.get("zellij_session") or "-"
            extra = ""
            if m.get("agent") == "agy" and slot in agy_by_slot:
                ad = agy_by_slot[slot]
                st = ad.get("state", "?")
                age = max(0, now - int(ad.get("updated_at", now)))
                if st in ("working", "tool_use") and age > 90:
                    st = "PROMPT_WAIT?"
                elif st == "reviewing":
                    st = "REVIEWING!"
                ctx = ad.get("ctx_pct")
                cid = (ad.get("conversation_id") or "")[:8]
                extra = f"  [{cid} state={st} ctx={ctx}% hb={age}s]"
            print(f"  {slot:22s}  agent={m.get('agent','?'):8s}  zellij={z:18s}  since={since}  cwd={m.get('workdir','?')}{extra}")

    if shutil.which("zellij"):
        res = subprocess.run(["zellij", "list-sessions", "--no-formatting"], capture_output=True, text=True)
        exited = [ln for ln in res.stdout.splitlines() if "EXITED" in ln]
        if exited:
            print("\n=== Exited Zellij Sessions (resurrect with `yolo-resurrect` / `zr`) ===")
            for ln in exited:
                print(f"  {ln}")

    if fleet_mode:
        print("\n=== Fleet Antigravity Sessions (VictoriaMetrics, last 6h) ===")
        try:
            q_state = urllib.parse.urlencode({"query": "last_over_time(agy_session_state_code[6h])"})
            q_hb = urllib.parse.urlencode({"query": "last_over_time(agy_session_heartbeat_ts[6h])"})
            q_ctx = urllib.parse.urlencode({"query": "last_over_time(agy_session_ctx_pct[6h])"})
            with urllib.request.urlopen(f"${vmQueryUrl}?{q_state}", timeout=4) as r:
                s_res = json.loads(r.read().decode()).get("data", {}).get("result", [])
            with urllib.request.urlopen(f"${vmQueryUrl}?{q_hb}", timeout=4) as r:
                h_res = json.loads(r.read().decode()).get("data", {}).get("result", [])
            with urllib.request.urlopen(f"${vmQueryUrl}?{q_ctx}", timeout=4) as r:
                c_res = json.loads(r.read().decode()).get("data", {}).get("result", [])

            def key_of(m: dict) -> tuple:
                return (m.get("host", "?"), m.get("slot", "-"), m.get("conversation_id", "?"), m.get("cwd", "?"))

            hb_map = {key_of(x["metric"]): int(float(x["value"][1])) for x in h_res}
            ctx_map = {key_of(x["metric"]): float(x["value"][1]) for x in c_res}
            code_names = {0: "idle", 1: "working", 2: "REVIEWING!", 3: "ERROR"}
            now = int(time.time())
            rows = []
            for x in s_res:
                k = key_of(x["metric"])
                code = int(float(x["value"][1]))
                hb = hb_map.get(k, 0)
                age = max(0, now - hb) if hb else -1
                label = code_names.get(code, str(code))
                if code == 1 and age > 90:
                    label = "WAITING_ON_PROMPT!"
                rows.append((hb, k, label, ctx_map.get(k, 0.0), age))
            rows.sort(reverse=True)
            if not rows:
                print("  (no fleet metrics recorded yet)")
            for _hb, (hst, slt, cid, cwd), label, ctx, age in rows:
                age_s = f"{age}s ago" if age >= 0 else "?"
                print(f"  {hst:12s}  {slt:20s}  [{cid}]  {label:18s}  ctx={ctx:4.0f}%  hb={age_s:10s}  cwd={cwd}")
        except Exception as e:
            print(f"  (VictoriaMetrics query failed: {e})")
  '';

  yoloResurrect = pkgs.writeShellScriptBin "yolo-resurrect" ''
    set -euo pipefail

    if [ "''${1:-}" = "--all" ] || [ "''${1:-}" = "-a" ]; then
      exited=$(zellij list-sessions --no-formatting 2>/dev/null | awk '/EXITED/ {print $1}')
      if [ -z "$exited" ]; then
        echo "No exited Zellij sessions to resurrect."
        exit 0
      fi
      for s in $exited; do
        echo "Resurrecting $s in background..."
        zellij attach --create-background --force-run-commands "$s"
      done
      exit 0
    fi

    if [ $# -ge 1 ]; then
      exec zellij attach --force-run-commands "$@"
    fi

    sessions=$(zellij list-sessions --no-formatting 2>/dev/null || true)
    if [ -z "$sessions" ]; then
      echo "No Zellij sessions found."
      exit 0
    fi

    if command -v fzf >/dev/null 2>&1; then
      picked=$(printf '%s\n' "$sessions" | fzf --height=40% --prompt="Resurrect/attach session> " | awk '{print $1}')
      if [ -n "$picked" ]; then
        exec zellij attach --force-run-commands "$picked"
      fi
    else
      printf '%s\n' "$sessions"
    fi
  '';

  # Antigravity statusline script (300ms throttled by agy, receives snake_case JSON on stdin):
  #   1. Pins exact conversation_id into YOLO_STATE_FILE (handles /fork & /resume live!)
  #      and pane/cwd resurrection cache for bare `agy` sessions.
  #   2. Pushes state transitions + 15s heartbeats to local state & VictoriaMetrics (:8428).
  #   3. Renders stacked status line `[<conv_id:0:8>] (<slot>) ctx:<pct>%`.
  agyStatuslineText = ''
    #!${pkgs.python3}/bin/python3
    import hashlib
    import json
    import os
    import pathlib
    import re
    import socket
    import subprocess
    import sys
    import time

    raw = sys.stdin.read()
    if not raw.strip():
        sys.exit(0)

    try:
        data = json.loads(raw)
    except Exception:
        sys.exit(0)

    conv_id = (data.get("conversation_id") or data.get("session_id") or "").strip()
    cwd = (data.get("cwd") or (data.get("workspace") or {}).get("current_dir") or os.getcwd()).strip()
    title = (data.get("conversation_title") or "").strip()
    agent_state = (data.get("agent_state") or "idle").strip()
    ctx = data.get("context_window") or {}
    used_pct = ctx.get("used_percentage")
    if used_pct is None:
        used_pct = 0

    base = pathlib.Path(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")) / "yolo-agents"
    slot = os.environ.get("YOLO_SLOT") or ""

    def atomic_write_text(path: pathlib.Path, content: str) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)
        tmp = path.with_suffix(path.suffix + f".tmp.{os.getpid()}")
        tmp.write_text(content, encoding="utf-8")
        os.replace(tmp, path)

    if conv_id:
        # 1. Update yolo-agy slot state file immediately (tracks /fork & /resume!)
        state_file = os.environ.get("YOLO_STATE_FILE") or ""
        if state_file:
            sf = pathlib.Path(state_file)
            try:
                cur = json.loads(sf.read_text(encoding="utf-8")) if sf.is_file() else {}
            except Exception:
                cur = {}
            if cur.get("agy_conversation_id") != conv_id:
                cur["agy_conversation_id"] = conv_id
                atomic_write_text(sf, json.dumps(cur, indent=2) + "\n")

        # 2. Update bare-agy Zellij pane + CWD resurrection pointers
        zs = os.environ.get("ZELLIJ_SESSION_NAME", "")
        zp = os.environ.get("ZELLIJ_PANE_ID", "")
        if zs and zp:
            pf = base / "agy-panes" / f"{zs}__{zp}.id"
            if not pf.is_file() or pf.read_text(encoding="utf-8").strip() != conv_id:
                atomic_write_text(pf, conv_id + "\n")
        if cwd:
            ch = hashlib.sha1(os.path.realpath(cwd).encode("utf-8")).hexdigest()[:12]
            cf = base / "agy-cwds" / f"{ch}.id"
            if not cf.is_file() or cf.read_text(encoding="utf-8").strip() != conv_id:
                atomic_write_text(cf, conv_id + "\n")

        # 3. Record local telemetry + throttled async push to VictoriaMetrics
        now = int(time.time())
        agy_file = base / "agy" / f"{conv_id}.json"
        prev = {}
        if agy_file.is_file():
            try:
                prev = json.loads(agy_file.read_text(encoding="utf-8"))
            except Exception:
                prev = {}

        state_changed = prev.get("state") != agent_state
        due_push = state_changed or (now - int(prev.get("last_pushed_at", 0)) >= 15)

        rec = {
            "conversation_id": conv_id,
            "title": title,
            "slot": slot or prev.get("slot") or "",
            "cwd": cwd,
            "state": agent_state,
            "ctx_pct": used_pct,
            "updated_at": now,
            "last_pushed_at": now if due_push else prev.get("last_pushed_at", 0),
        }
        atomic_write_text(agy_file, json.dumps(rec) + "\n")

        if due_push:
            host = os.environ.get("YOLO_HOST") or "${hostname}" or socket.gethostname().split(".")[0]
            code_map = {
                "idle": 0,
                "working": 1,
                "tool_use": 1,
                "initializing": 1,
                "authenticating": 2,
                "reviewing": 2,
                "error": 3,
            }
            code = code_map.get(agent_state, 1)

            def esc_tag(v: str) -> str:
                return re.sub(r"[,= \t\n\\]", "_", v or "-")

            dir_label = os.path.basename(cwd.rstrip("/")) or "root"
            slot_tag = rec["slot"] or dir_label
            line = (
                f"agy_session,host={esc_tag(host)},slot={esc_tag(slot_tag)},"
                f"conversation_id={esc_tag(conv_id[:8])},cwd={esc_tag(dir_label)} "
                f"state_code={code}i,ctx_pct={float(used_pct):.1f},heartbeat_ts={now}i\n"
            )
            try:
                subprocess.Popen(
                    ["${pkgs.curl}/bin/curl", "-fsS", "--max-time", "1.5", "-X", "POST", "--data-binary", line, "${vmWriteUrl}"],
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    close_fds=True,
                    start_new_session=True,
                )
            except Exception:
                pass

    # 4. Stacked status line output (appended below agy's native status bar)
    if conv_id:
        parts = [f"[{conv_id[:8]}]"]
        if slot:
            parts.append(slot)
        parts.append(f"ctx:{used_pct}%")
        if title:
            short_t = title if len(title) <= 36 else title[:33] + "..."
            parts.append(short_t)
        sys.stdout.write(" · ".join(parts))
  '';

  # Antigravity lifecycle hook handler (~/.gemini/config/hooks.json, camelCase JSON on stdin).
  # Strictly obeys hook stdout schemas:
  #   - Stop -> {"decision":"stop"} (never blocks stop or loops)
  #   - SessionStart / PreInvocation / PostToolUse -> {}
  agyHookStateText = ''
    #!${pkgs.python3}/bin/python3
    import json
    import os
    import pathlib
    import re
    import socket
    import subprocess
    import sys
    import time

    mode = sys.argv[1] if len(sys.argv) > 1 else "working"
    raw = sys.stdin.read()
    try:
        payload = json.loads(raw) if raw.strip() else {}
    except Exception:
        payload = {}

    event_name = payload.get("hookEventName") or ""
    conv_id = (payload.get("conversationId") or "").strip()
    cwd = (payload.get("cwd") or "").strip()
    if not cwd:
        wps = payload.get("workspacePaths") or []
        cwd = wps[0] if wps else os.getcwd()

    if conv_id:
        now = int(time.time())
        base = pathlib.Path(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state")) / "yolo-agents"
        agy_file = base / "agy" / f"{conv_id}.json"
        agy_file.parent.mkdir(parents=True, exist_ok=True)
        prev = {}
        if agy_file.is_file():
            try:
                prev = json.loads(agy_file.read_text(encoding="utf-8"))
            except Exception:
                prev = {}

        slot = os.environ.get("YOLO_SLOT") or prev.get("slot") or ""
        ctx_pct = prev.get("ctx_pct", 0)
        rec = {
            "conversation_id": conv_id,
            "title": prev.get("title", ""),
            "slot": slot,
            "cwd": cwd,
            "state": mode,
            "ctx_pct": ctx_pct,
            "updated_at": now,
            "last_pushed_at": now,
        }
        tmp = agy_file.with_suffix(f".json.tmp.{os.getpid()}")
        tmp.write_text(json.dumps(rec) + "\n", encoding="utf-8")
        os.replace(tmp, agy_file)

        host = os.environ.get("YOLO_HOST") or "${hostname}" or socket.gethostname().split(".")[0]
        code = 0 if mode == "idle" else 1

        def esc_tag(v: str) -> str:
            return re.sub(r"[,= \t\n\\]", "_", v or "-")

        dir_label = os.path.basename(cwd.rstrip("/")) or "root"
        slot_tag = slot or dir_label
        line = (
            f"agy_session,host={esc_tag(host)},slot={esc_tag(slot_tag)},"
            f"conversation_id={esc_tag(conv_id[:8])},cwd={esc_tag(dir_label)} "
            f"state_code={code}i,ctx_pct={float(ctx_pct):.1f},heartbeat_ts={now}i\n"
        )
        try:
            subprocess.Popen(
                ["${pkgs.curl}/bin/curl", "-fsS", "--max-time", "1.5", "-X", "POST", "--data-binary", line, "${vmWriteUrl}"],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                close_fds=True,
                start_new_session=True,
            )
        except Exception:
            pass

    if event_name == "Stop" or mode == "idle":
        sys.stdout.write('{"decision":"stop"}\n')
    else:
        sys.stdout.write("{}\n")
  '';

  agyHooksJson = builtins.toJSON {
    fleet-telemetry = {
      SessionStart = [
        {
          type = "command";
          command = "~/.local/bin/agy-state idle";
          timeout = 3;
        }
      ];
      PreInvocation = [
        {
          type = "command";
          command = "~/.local/bin/agy-state working";
          timeout = 3;
        }
      ];
      PostToolUse = [
        {
          matcher = "*";
          hooks = [
            {
              type = "command";
              command = "~/.local/bin/agy-state working";
              timeout = 3;
            }
          ];
        }
      ];
      Stop = [
        {
          type = "command";
          command = "~/.local/bin/agy-state idle";
          timeout = 3;
        }
      ];
    };
  };
in
lib.mkMerge [
  {
    home.packages = [
      bwrapYolo
      yoloRunner
      agyResurrect
      yoloLs
      yoloResurrect
      (mkYoloWrapper "claude")
      (mkYoloWrapper "agy")
      (mkYoloWrapper "opencode")
      (mkYoloWrapper "pi")
      (mkYoloWrapper "kimi")
      (mkYoloWrapper "codex")
    ];
  }

  # Only deploy Antigravity statusline, lifecycle hooks, and VictoriaMetrics
  # telemetry on hosts where programs.antigravity-cli is enabled (keeps corporate
  # hosts devdesktop/gravidesktop/work-laptop completely untouched).
  (lib.mkIf config.programs.antigravity-cli.enable {
    home.file.".gemini/antigravity-cli/statusline.sh" = {
      executable = true;
      text = agyStatuslineText;
    };

    home.file.".local/bin/agy-state" = {
      executable = true;
      text = agyHookStateText;
    };

    home.file.".gemini/config/hooks.json".text = agyHooksJson;

    # Merge `notifications` and `statusLine` into the mutable settings.json
    # in-place so agy's runtime `permissions` and `trustedWorkspaces` edits stay writable.
    home.activation.antigravityCliSettings = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      settings_dir="${config.home.homeDirectory}/.gemini/antigravity-cli"
      settings_file="$settings_dir/settings.json"
      mkdir -p "$settings_dir"
      if [ ! -s "$settings_file" ]; then
        printf '{}\n' > "$settings_file"
      fi
      if tmp_json=$(${pkgs.jq}/bin/jq '
        .notifications = true
        | .statusLine = {
            type: "command",
            command: "~/.gemini/antigravity-cli/statusline.sh",
            stack_with_default: true,
            enabled: true
          }
      ' "$settings_file" 2>/dev/null); then
        printf '%s\n' "$tmp_json" > "$settings_file.tmp"
        chmod 0600 "$settings_file.tmp"
        mv "$settings_file.tmp" "$settings_file"
      fi
    '';
  })
];
}
