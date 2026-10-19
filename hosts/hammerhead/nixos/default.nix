{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "hammerhead";

  # Headless edge server; cross-compiled armv7l (crossSafe trims the `cli`
  # bits that don't cross-compile).
  embedded = {
    enable = true;
    serialConsole = "ttyMSM0";
    crossSafe = true;
  };
  hardware.bluetooth.enable = lib.mkForce false;

  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # The mobile-nixos rootfs is ext4; no btrfs anywhere on this host.
  services.btrfs.autoScrub.enable = lib.mkForce false;

  # Bootloader updates: rewrite the boot partition from the activation hook
  # (hash-guarded) so colmena deploys keep the kernel in sync.
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "install-hammerhead-bootimg" ''
      set -euo pipefail
      img="${config.mobile.outputs.android.android-bootimg}"
      part=/dev/disk/by-partlabel/boot
      marker=/var/lib/nixos/.bootimg-sha256
      new="$(${pkgs.coreutils}/bin/sha256sum "$img" | ${pkgs.coreutils}/bin/cut -d' ' -f1)"
      old=""
      [ -f "$marker" ] && old="$(${pkgs.coreutils}/bin/cat "$marker")"
      if [ "$new" != "$old" ]; then
        echo "install-hammerhead-bootimg: writing $img -> $part"
        ${pkgs.coreutils}/bin/dd if="$img" of="$part" bs=4M conv=fsync status=none
        ${pkgs.coreutils}/bin/mkdir -p /var/lib/nixos
        echo "$new" > "$marker"
      fi
    '';
  };

  # embedded adds console=ttyMSM0 via serialConsole; the device module adds
  # the msm cmdline params. Drop the tty1 duplicate from embedded — the
  # Nexus 5 has no usable UART without opening it, display console suffices.
  boot.kernelParams = lib.mkAfter [ "console=tty1" ];

  # Bring-up credential for the on-device console (SSH is key-only).
  # TODO: remove once on netbird and SSH-reachable.
  users.users.root.initialPassword = lib.mkForce "hammerhead";
  users.users.z-247.initialPassword = lib.mkForce "hammerhead";

  # WiFi: shared iwd + sops wifi-secrets stack from `cli`. Mainline brcmfmac
  # on a 6.11 kernel works with iwd. Same first-boot key flow as herolte
  # (grab host key via console, add &hammerhead_ssh/&hammerhead_age to
  # .sops.yaml in nix-config-private, sops updatekeys secrets/wifi.yaml
  # there, push + nix flake update private, colmena apply).

  systemd.network.networks."20-wifi" = {
    matchConfig.Name = "wlan0";
    linkConfig.RequiredForOnline = "no";
  };

  systemd.settings.Manager.RuntimeWatchdogSec = "30";

  system.stateVersion = "26.05";
}
