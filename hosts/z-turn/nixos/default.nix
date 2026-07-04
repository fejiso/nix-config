{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "z-turn";

  # Resource-constrained ARM board, cross-compiled (armv7l). `crossSafe` forces
  # bash and disables the `cli` components that don't cross-compile or run a
  # target binary at build time (fish, nix-ld, kmscon, fontconfig fc-cache,
  # nix-serve, redistributable firmware) — all in the shared embedded module now.
  embedded = {
    enable = true;
    serialConsole = "ttyPS0";   # Zynq Cadence (xuartps) UART
    crossSafe = true;
  };

  # base.nix enables graphics unconditionally; this board has none.
  hardware.graphics.enable = lib.mkForce false;

  # ARM uses generic-extlinux-compatible, not systemd-boot / UEFI.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Bring-up credential: the serial console login is otherwise unusable (SSH is
  # key-only). TODO: remove once the board is on netbird and SSH-reachable.
  users.users.root.initialPassword = lib.mkForce "zturn";
  users.users.z-247.initialPassword = lib.mkForce "zturn";

  # PL bitstream loader: `load-fpga design.bit.bin` over SSH/netbird. No JTAG.
  environment.systemPackages = [ pkgs.load-fpga ];

  system.stateVersion = "25.05";
}
