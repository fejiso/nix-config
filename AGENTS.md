# Agent rules for this repo

## Secrets / private repo — HARD RULES

- **NEVER run `sops` (encrypt or decrypt) yourself.** Secrets are encrypted by
  the user, on their initiative only.
- Creating and editing files in the private repo checkout (`~/dev/nix-config-private`,
  flake input `private`) is allowed — just never run `sops` to encrypt or decrypt.
- Writing *scripts* that invoke sops for the user to run later (e.g.
  `~/blinkenlights/fetch-secrets.sh`, `flake-modules/blinkenlights.nix` apps)
  is fine — that is code, not running sops yourself.

## Repo conventions

- Flake is dendritic (flake-parts + import-tree of `flake-modules/`).
- Fleet service registry: `flake-modules/fleet-services.nix` (+ options in
  `flake-modules/options.nix`), consumed by `system-modules/ingress.nix` and
  `system-modules/gatus.nix`.
- New files must be `git add`-ed before `nix eval`/`flake check` — git flakes
  ignore untracked files.
- ESP32 firmware lives in the separate `~/blinkenlights` repo
  (`git+ssh://git@github.com/fejiso/blinkenlights.git`, flake input
  `blinkenlights`, flake = false).
