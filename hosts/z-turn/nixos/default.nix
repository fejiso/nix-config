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

  # Headless board — trim things from the shared `default` that either don't
  # cross-compile to armv7l or are pointless here:
  #  - gutenprint (CUPS printing) runs a target test binary at build time.
  #  - fish 4.x (Rust) cross-build is broken; use bash for system management.
  services.printing.enable = lib.mkForce false;
  programs.fish.enable = lib.mkForce false;
  users.defaultUserShell = lib.mkForce pkgs.bash;
  users.users.z-247.shell = lib.mkForce pkgs.bash;

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

  # ~753 MiB of blobs for discrete GPUs / WiFi / BT this board doesn't have.
  # The Zynq PS peripherals (GEM ethernet, USB, SD/MMC, UART) need no firmware
  # upload. If a USB WiFi/BT dongle is ever attached, add only that chip's
  # firmware to hardware.firmware (check `dmesg | grep -i firmware`).
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = lib.mkForce [ ];

  # ARM uses generic-extlinux-compatible, not systemd-boot / UEFI.
  boot.loader.systemd-boot.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Bring-up credential: without a password, the serial console login is
  # unusable (and SSH is key-only), so a failed network leaves no way in.
  users.users.root.initialPassword = lib.mkForce "zturn";
  users.users.z-247.initialPassword = lib.mkForce "zturn";

  # The login "System error" root cause was the btrfs image's `/` being owned by
  # uid 1000 (make-btrfs-fs bug), which made systemd-tmpfiles refuse every path
  # ("unsafe path transition", exit 73) so /var/lib/lastlog was never created
  # and pam_lastlog2 (session required) aborted login. Fixed for all SD hosts in
  # the shared sd-image-btrfs module (fix-sd-root-ownership runs before
  # tmpfiles-setup). Nothing z-turn-specific is needed here anymore.

  system.stateVersion = "25.05";
}
