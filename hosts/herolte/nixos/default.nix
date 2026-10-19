{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "herolte";

  # Headless edge server on a phone: resource-constrained ARM base,
  # cross-compiled from x86 (crossSafe trims the `cli` bits that don't
  # cross-compile or run target binaries at build time).
  embedded = {
    enable = true;
    crossSafe = true;
  };
  hardware.bluetooth.enable = lib.mkForce false;

  # crossSafe empties hardware.firmware (redistributable blobs don't
  # cross-compile); re-add just the BCM4359 WiFi package from the device port.
  hardware.firmware = lib.mkForce [ config.mobile.device.firmware ];

  # base.nix enables graphics + systemd-boot; a phone has no UEFI and the
  # Mali GPU is unused headless.
  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # The mobile-nixos rootfs is ext4, not btrfs (the repo's SD stack isn't
  # used here), and the shared base enables btrfs autoScrub unconditionally.
  services.btrfs.autoScrub.enable = lib.mkForce false;
  boot.loader.efi.canTouchEfiVariables = lib.mkForce false;

  # Bootloader updates: mobile-nixos' android-bootimg derivation is a plain
  # build product of this very configuration, so colmena/nixos-rebuild can
  # refresh the BOOT partition on activation. Guarded by a hash so routine
  # stage-2-only switches don't rewrite the partition.
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "install-herolte-bootimg" ''
      set -euo pipefail
      img="${config.mobile.outputs.android.android-bootimg}"
      part=/dev/disk/by-partlabel/BOOT
      marker=/var/lib/nixos/.bootimg-sha256
      new="$(${pkgs.coreutils}/bin/sha256sum "$img" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
      old=""
      [ -f "$marker" ] && old="$(${pkgs.coreutils}/bin/cat "$marker")"
      if [ "$new" != "$old" ]; then
        echo "install-herolte-bootimg: writing $img -> $part"
        ${pkgs.coreutils}/bin/dd if="$img" of="$part" bs=4M conv=fsync status=none
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/nixos
        echo "$new" > "$marker"
      fi
    '';
  };

  # Console: no UART jig — kernel messages + getty on the display.
  # (embedded's serialConsole default ttyS0 doesn't exist here.)
  boot.kernelParams = lib.mkForce [ "console=tty1" ];

  # Bring-up credential for the on-device console (SSH is key-only).
  # TODO: remove once on netbird and SSH-reachable.
  users.users.root.initialPassword = lib.mkForce "herolte";
  users.users.z-247.initialPassword = lib.mkForce "herolte";

  # adb over the USB gadget for screen-less bring-up/debugging.
  mobile.adbd.enable = true;

  # WiFi comes from the shared `cli` stack: iwd standalone + the sops-managed
  # `wifi-secrets` (secrets/wifi.yaml) synced into /var/lib/iwd. NOTE: iwd on
  # the ancient 3.18 downstream dhd driver is UNVERIFIED — if association
  # fails at bring-up, flip this host to wpa_supplicant
  # (networking.wireless.enable) instead.
  #
  # First-boot flow (chicken-and-egg: wifi.yaml isn't encrypted for the
  # phone's host key yet): boot, log in on the display or `adb shell`, grab
  # the SSH host key (ssh-keyscan localhost), add &herolte_ssh/&herolte_age
  # to .sops.yaml in the nix-config-private repo, `sops updatekeys
  # secrets/wifi.yaml` there, push, `nix flake update private`, then colmena
  # apply.

  # Don't let a missing AP stall boot into multi-user.
  systemd.network.networks."20-wifi" = {
    matchConfig.Name = "wlan0";
    linkConfig.RequiredForOnline = "no";
  };

  # Watchdog baseline (s3c2410-wdt on exynos8890): userspace hang resets the
  # phone after 30s.
  systemd.settings.Manager.RuntimeWatchdogSec = "30";

  system.stateVersion = "26.05";
}
