{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "kr260";

  # Resource-constrained ARM board, cross-compiled (aarch64). `crossSafe`
  # disables the `cli` components that don't cross-compile or run a target
  # binary at build time (nix-ld, kmscon, fontconfig fc-cache, nix-serve,
  # redistributable firmware) — all in the shared embedded module now.
  embedded = {
    enable = true;
    serialConsole = "ttyPS0";   # ZynqMP Cadence (xuartps) UART
    crossSafe = true;
  };

  # base.nix enables graphics unconditionally; this board has none.
  hardware.graphics.enable = lib.mkForce false;

  # ARM uses generic-extlinux-compatible, not systemd-boot / UEFI.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Bring-up credential: the serial console login is otherwise unusable (SSH is
  # key-only). TODO: remove once the board is on netbird and SSH-reachable.
  users.users.root.initialPassword = lib.mkForce "kr260";
  users.users.z-247.initialPassword = lib.mkForce "kr260";

  # PL bitstream loader: `load-fpga design.bit.bin` over SSH/netbird. No JTAG.
  environment.systemPackages = [ pkgs.load-fpga ];

  # Watchdog baseline (fpgapuzzler postmortem 2026-09-22: a wedged PL AXI
  # transaction hard-hung the board; the SoC has two Cadence SWDTs and
  # /dev/watchdog0 already exists). systemd pets every 15 s; if userspace
  # dies, the SWDT resets the board after 30 s. NOTE: this alone does NOT
  # catch a single-process PL AXI stall (systemd stays alive) — the
  # PL-aware petter (fpgapuzzler host/fpga_wdt.c) covers that. Deploy after
  # the running 72h M1 soak completes (reboot kills it).
  systemd.settings.Manager.RuntimeWatchdogSec = "30";

  system.stateVersion = "25.05";
}
