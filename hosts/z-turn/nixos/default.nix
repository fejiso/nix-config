{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "z-turn";

  # The shared `default` module forces the full Wayland desktop home (linux-default:
  # niri/sway/noctalia/…) onto every host. That's absurd to cross-compile for a
  # headless armv7l board — drop home-manager here entirely.
  home-manager.users = lib.mkForce { };

  # Resource-constrained ARM optimizations + serial console.
  embedded = {
    enable = true;
    serialConsole = "ttyPS0";   # Zynq Cadence (xuartps) UART
  };

  # ext4 root, no btrfs.
  services.btrfs.autoScrub.enable = lib.mkForce false;

  # Headless board — trim things from the shared `default` that either don't
  # cross-compile to armv7l or are pointless here:
  #  - gutenprint (CUPS printing) runs a target test binary at build time.
  #  - fish 4.x (Rust) cross-build is broken; use bash for system management.
  services.printing.enable = lib.mkForce false;
  programs.fish.enable = lib.mkForce false;
  users.defaultUserShell = lib.mkForce pkgs.bash;
  users.users.z-247.shell = lib.mkForce pkgs.bash;

  # Drop the Reticulum units (rnsd, lxmd) — they pull python rns/lxmf -> esptool,
  # which fails to cross-compile. mkForce {} so the units don't reference them.
  systemd.services.rnsd = lib.mkForce { };
  systemd.services.lxmd = lib.mkForce { };
  # No display -> no fontconfig (its fc-cache step runs a target binary).
  fonts.fontconfig.enable = lib.mkForce false;

  # Don't serve a binary cache from a tiny board — nix-serve is Perl/Plack and
  # its module stack doesn't cross-compile to armv7l.
  services.nix-serve.enable = lib.mkForce false;

  # nix-ld (Rust, runs foreign dynamic binaries) doesn't cross-compile; kmscon
  # is a DRM/KMS console pointless on a headless board.
  programs.nix-ld.enable = lib.mkForce false;
  services.kmscon.enable = lib.mkForce false;

  # Disable x86-specific graphics paths.
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;

  # ARM uses generic-extlinux-compatible, not systemd-boot / UEFI.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  system.stateVersion = "25.05";
}
