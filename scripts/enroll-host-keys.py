#!/usr/bin/env python3
"""Surgically enroll or update a host's SSH + age public keys in:
  1. nix-config-private/.sops.yaml (preserving comments, anchors, and aliases)
  2. nix-config/lib/build-keys.nix
"""

from __future__ import annotations

import pathlib
import re
import sys


TUNGSTEN_OLD_BLACKTOP_SSH = "AAAAC3NzaC1lZDI1NTE5AAAAINQePaMUwEu3oPfVMg/Yk9BiX6QbDmxRBC3Icnd1GkGQ"


def normalize_ssh_pub(raw: str) -> tuple[str, str]:
    parts = raw.strip().split()
    if len(parts) < 2 or parts[0] != "ssh-ed25519":
        raise SystemExit(f"Expected 'ssh-ed25519 <base64>', got: {raw!r}")
    return f"{parts[0]} {parts[1]}", parts[1]


def update_sops_yaml(sops_path: pathlib.Path, hostname: str, ssh_pub: str, age_pub: str) -> bool:
    orig = sops_path.read_text()
    text = orig

    anchor_base = hostname.replace("-", "_")
    ssh_anchor = f"{anchor_base}_ssh"
    age_anchor = f"{anchor_base}_age"

    # Guard: if enrolling revived `blacktop` and `.sops.yaml` still has tungsten's
    # migrated disk key under `&blacktop_ssh`, rename that anchor/alias to tungsten first.
    if (
        hostname == "blacktop"
        and TUNGSTEN_OLD_BLACKTOP_SSH in text
        and "&tungsten_ssh " not in text
        and re.search(rf"^\s*-\s*&blacktop_ssh\s+.*{re.escape(TUNGSTEN_OLD_BLACKTOP_SSH)}", text, re.M)
    ):
        text = re.sub(r"(&|\*)blacktop_ssh\b", r"\1tungsten_ssh", text)
        text = re.sub(r"(&|\*)blacktop_age\b", r"\1tungsten_age", text)

    lines = text.splitlines()

    # 1. Update or insert `&<host>_ssh` in keys:
    ssh_pat = re.compile(rf"^(\s*-\s*&{re.escape(ssh_anchor)}\s+).*$")
    if any(ssh_pat.match(ln) for ln in lines):
        lines = [ssh_pat.sub(rf"\g<1>{ssh_pub}", ln) for ln in lines]
    else:
        last_ssh_idx = max(
            i for i, ln in enumerate(lines)
            if re.match(r"^\s*-\s*&[A-Za-z0-9_]+_ssh\b", ln) and "&user_ssh" not in ln
        )
        lines.insert(last_ssh_idx + 1, f"  - &{ssh_anchor} {ssh_pub}")

    # 2. Update or insert `&<host>_age` in keys:
    age_pat = re.compile(rf"^(\s*-\s*&{re.escape(age_anchor)}\s+).*$")
    if any(age_pat.match(ln) for ln in lines):
        lines = [age_pat.sub(rf"\g<1>{age_pub}", ln) for ln in lines]
    else:
        last_age_idx = max(
            i for i, ln in enumerate(lines)
            if re.match(r"^\s*-\s*&[A-Za-z0-9_]+_age\b", ln) and "&user_age" not in ln
        )
        lines.insert(last_age_idx + 1, f"  - &{age_anchor} {age_pub}")

    # 3. Ensure `*<host>_ssh` and `*<host>_age` appear in every host creation_rule
    #    (identified by rules that already include `*butthead_ssh` / `*butthead_age`).
    out: list[str] = []
    i = 0
    while i < len(lines):
        ln = lines[i]
        if re.match(r"^\s*-\s*path_regex:\s*", ln):
            j = i + 1
            while j < len(lines) and not re.match(r"^\s*-\s*path_regex:\s*", lines[j]):
                j += 1
            block = lines[i:j]
            has_host_ssh = any(re.match(r"^\s*-\s*\*butthead_ssh\b", b) for b in block)
            has_host_age = any(re.match(r"^\s*-\s*\*butthead_age\b", b) for b in block)
            if has_host_ssh and not any(re.match(rf"^\s*-\s*\*{re.escape(ssh_anchor)}\b", b) for b in block):
                idx = next(k for k, b in enumerate(block) if re.match(r"^\s*-\s*\*butthead_ssh\b", b))
                indent = re.match(r"^(\s*)-\s*\*", block[idx]).group(1)
                block.insert(idx + 1, f"{indent}- *{ssh_anchor}")
            if has_host_age and not any(re.match(rf"^\s*-\s*\*{re.escape(age_anchor)}\b", b) for b in block):
                idx = next(k for k, b in enumerate(block) if re.match(r"^\s*-\s*\*butthead_age\b", b))
                indent = re.match(r"^(\s*)-\s*\*", block[idx]).group(1)
                block.insert(idx + 1, f"{indent}- *{age_anchor}")
            out.extend(block)
            i = j
        else:
            out.append(ln)
            i += 1

    new_text = "\n".join(out) + "\n"
    if new_text != orig:
        sops_path.write_text(new_text)
        return True
    return False


def update_build_keys_nix(nix_path: pathlib.Path, hostname: str, ssh_b64: str) -> bool:
    orig = nix_path.read_text()
    attr_key = f'"{hostname}"' if not re.match(r"^[A-Za-z_][A-Za-z0-9_-]*$", hostname) else hostname

    block_pat = re.compile(
        rf"(^\s*{re.escape(attr_key)}\s*=\s*\{{[^\}}]*?hostPublicKey\s*=\s*\")([^\"]*)(\";)",
        re.M | re.S,
    )
    if block_pat.search(orig):
        new_text = block_pat.sub(rf"\g<1>{ssh_b64}\g<3>", orig, count=1)
    else:
        entry = (
            f"    {attr_key} = {{\n"
            f'      hostPublicKey = "{ssh_b64}";\n'
            f'      nixPublicKey = "";\n'
            f"    }};\n"
        )
        # Insert right before the closing `  };` of `keys = { ... };`
        close_pat = re.compile(r"\n(\s*\};\s*\n\}\s*)$")
        if not close_pat.search(orig):
            raise SystemExit(f"Could not locate closing `keys` brace in {nix_path}")
        new_text = close_pat.sub(f"\n{entry}\\1", orig, count=1)

    if new_text != orig:
        nix_path.write_text(new_text)
        return True
    return False


def main() -> None:
    if len(sys.argv) != 6:
        raise SystemExit(
            f"Usage: {sys.argv[0]} <hostname> <ssh-ed25519-pubkey> <age-pubkey> <sops.yaml> <build-keys.nix>"
        )
    hostname = sys.argv[1]
    ssh_pub, ssh_b64 = normalize_ssh_pub(sys.argv[2])
    age_pub = sys.argv[3].strip()
    if not age_pub.startswith("age1"):
        raise SystemExit(f"Invalid age recipient: {age_pub!r}")

    sops_path = pathlib.Path(sys.argv[4])
    nix_path = pathlib.Path(sys.argv[5])

    sops_changed = update_sops_yaml(sops_path, hostname, ssh_pub, age_pub)
    nix_changed = update_build_keys_nix(nix_path, hostname, ssh_b64)
    print(f"enrolled {hostname}: sops_yaml_changed={sops_changed} build_keys_changed={nix_changed}")


if __name__ == "__main__":
    main()
