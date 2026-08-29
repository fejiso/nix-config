{ ... }: {
  flake.modules.nixos.bcachefs =
{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.hardware.bcachefs-support;
in
{
  options.hardware.bcachefs-support = {
    enable = mkEnableOption "bcachefs filesystem support (kernel module + bcachefs-tools)";

    initrd = mkOption {
      type = types.bool;
      default = false;
      description = "Also enable bcachefs in the initrd (needed if any bcachefs filesystem is mounted early, e.g. as root)";
    };
  };

  config = mkIf cfg.enable {
    boot.supportedFilesystems = [ "bcachefs" ];
    boot.initrd.supportedFilesystems = mkIf cfg.initrd [ "bcachefs" ];

    environment.systemPackages = [ pkgs.bcachefs-tools ];

    # Keep the *booted* generation alive so its kernel modules stay loadable
    # for the running kernel after a switch to a newer kernel. NixOS kmod
    # looks in /run/booted-system/kernel-modules first, but that symlink
    # dangles if age-based GC deletes the booted generation. angrr prunes
    # system generations by policy instead (see nix-garbage-collect, which
    # skips --delete-older-than when angrr is enabled).
    services.angrr = {
      enable = true;
      timer.enable = true;
      settings.profile-policies.system = {
        profile-paths = [ "/nix/var/nix/profiles/system" ];
        keep-booted-system = true;
        keep-current-system = true;
        keep-since = "14d";
        keep-latest-n = 5;
      };
    };

    # angrr can only protect generations that still have a profile link; if
    # age-based GC already deleted the booted generation's link, pin the
    # booted system directly so its kernel modules can never be collected
    # from underneath the running kernel.
    systemd.services.pin-booted-system = {
      description = "GC-root the booted system (keeps running kernel's modules)";
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        rm -f /nix/var/nix/gcroots/booted-system
        ${config.nix.package}/bin/nix-store --add-root /nix/var/nix/gcroots/booted-system \
          -r "$(readlink -f /run/booted-system)"
      '';
    };
  };
}
;
}
