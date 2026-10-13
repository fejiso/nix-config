{ inputs, outputs, lib, config, pkgs, hostname, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  networking.hostName = "austin";

  # Headless; cross-compiled armv7l (crossSafe trims non-cross-safe cli bits).
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

  # No on-device boot.img rewrite (WIP port; bootloader state fragile —
  # reflash via fastboot after the unlock exploit, see devices/amazon-*
  # comments). This hook just warns when the boot image changed.
  boot.loader.external = {
    enable = true;
    installHook = pkgs.writeShellScript "austin-bootimg-note" ''
      echo "austin: kernel/stage-1 changes are NOT flashed automatically."
      echo "austin: reflash via fastboot: fastboot flash boot ${config.mobile.outputs.android.android-bootimg}"
    '';
  };

  # Bring-up credential for the on-device console (SSH is key-only).
  # TODO: remove once reachable over SSH.
  users.users.root.initialPassword = lib.mkForce "austin";
  users.users.z-247.initialPassword = lib.mkForce "austin";

  # WiFi: NOT wired up (proprietary consys blobs / no driver — see the device
  # port comments). The iwd/sops stack from cli stays inert until then.

  systemd.settings.Manager.RuntimeWatchdogSec = "30";

  system.stateVersion = "26.05";
}
