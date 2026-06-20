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
  flake.modules.nixos.sd-image-btrfs = {
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
