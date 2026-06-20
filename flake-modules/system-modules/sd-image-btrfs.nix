{ ... }: {
  # Generic btrfs root for all SD-image hosts. mk-host wires these into every
  # host built with `sdImage = true` (the runtime module into the system, the
  # build module into the image), so individual hosts only declare the
  # arch/firmware/console specifics in their hosts/<name>/nixos/sd-image.nix.
  #
  # The image's root partition is created directly as btrfs (make-btrfs-fs),
  # sized to its contents, and grown to fill the card on first boot via
  # growPartition + x-systemd.growfs — no ext4 + convert-on-firstboot dance.

  # Runtime (and image) system config.
  flake.modules.nixos.sd-image-btrfs = { pkgs, ... }: {
    boot.loader.grub.enable = false;
    boot.loader.generic-extlinux-compatible.enable = true;

    # Grow the root partition to fill the card, then grow the btrfs onto it
    # (filesystem-agnostic, unlike the sd-image module's ext4-only expandOnBoot).
    boot.growPartition = true;

    fileSystems."/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [ "compress=zstd" "noatime" "x-systemd.growfs" ];
    };
    fileSystems."/boot" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
    };

    # make-btrfs-fs builds the image's `/` and `/nix` owned by the build user
    # (uid 1000), not root: its mkdir/cp run outside the fakeroot wrapper, so
    # `mkfs.btrfs -r` records the wrong owner. systemd-tmpfiles then refuses
    # every path under `/` with "unsafe path transition" and exits 73 — so
    # /var/empty, /var/spool, /var/lib/lastlog etc. are never created, and
    # `pam_lastlog2` (session required) makes that a fatal "System error" at
    # login, while x-systemd.growfs fails the same way. Re-root the offending
    # dirs before tmpfiles-setup runs. Idempotent; cheap; first boot is what
    # matters but it's harmless every boot.
    systemd.services.fix-sd-root-ownership = {
      description = "Re-own / and /nix to root (make-btrfs-fs leaves them uid 1000)";
      wantedBy = [ "sysinit.target" ];
      after = [ "systemd-remount-fs.service" ];
      before = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.coreutils}/bin/chown 0:0 / /nix /nix/store";
      };
    };
  };

  # Image-build-only overrides (the `sdImage` option only exists where an
  # arch-specific sd-image module is imported, i.e. the image config).
  flake.modules.nixos.sd-image-btrfs-build =
    { lib, modulesPath, ... }: {
      sdImage = {
        compressImage = true;
        # ext4-specific resize2fs; we grow via growPartition + growfs instead.
        expandOnBoot = false;
        rootFilesystemCreator = modulesPath + "/../lib/make-btrfs-fs.nix";
      };
      # The image build only needs the btrfs root; the FAT firmware partition is
      # populated separately and must not be a required mount during the build.
      fileSystems = lib.mkForce {
        "/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "btrfs";
        };
      };
    };
}
