{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "tissot";

  # Headless edge server, cross-compiled from x86 (crossSafe, like herolte).
  embedded = {
    enable = true;
    crossSafe = true;
  };
  hardware.bluetooth.enable = lib.mkForce false;

  hardware.graphics.enable = lib.mkForce false;
  hardware.graphics.enable32Bit = lib.mkForce false;
  boot.loader.systemd-boot.enable = lib.mkForce false;

  # The mobile-nixos rootfs is ext4; no btrfs anywhere on this host.
  services.btrfs.autoScrub.enable = lib.mkForce false;

  # NO on-device boot.img rewrite: the boot partition holds lk2nd, and the
  # NixOS boot image lives at an offset managed by lk2nd's fastboot. Kernel /
  # stage-1 updates require reflashing through lk2nd
  # (scripts/flash-tissot.sh). This hook just warns.
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "tissot-bootimg-note" ''
      echo "tissot: kernel/stage-1 changes are NOT flashed automatically (lk2nd)."
      echo "tissot: if ${config.mobile.outputs.android.android-bootimg} changed,"
      echo "tissot: reflash via lk2nd fastboot: fastboot flash boot <that file>"
    '';
  };

  # Bring-up credential for the on-device console (SSH is key-only).
  # TODO: remove once on netbird and SSH-reachable.
  users.users.root.initialPassword = lib.mkForce "tissot";
  users.users.z-247.initialPassword = lib.mkForce "tissot";

  # WiFi: shared iwd + sops wifi-secrets stack from `cli`. Mainline wcn36xx
  # works with iwd; firmware comes from the modem partition via the device's
  # tissot-wifi-firmware service. Same first-boot key flow as herolte.

  systemd.network.networks."20-wifi" = {
    matchConfig.Name = "wlan0";
    linkConfig.RequiredForOnline = "no";
  };

  systemd.settings.Manager.RuntimeWatchdogSec = "30";

  system.stateVersion = "26.05";
}
