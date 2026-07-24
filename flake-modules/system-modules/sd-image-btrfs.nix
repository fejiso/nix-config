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

    # SD-card longevity mount options: zstd compresses data before it hits the
    # flash (fewer bytes written = less write amplification), commit=120 batches
    # metadata updates every 120s instead of the 30s default, and discard=async
    # feeds the card's FTL free-block info for its internal GC. (space_cache=v2
    # is omitted: free-space-tree is the default on modern kernels.)
    fileSystems."/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "btrfs";
      options = [
        "noatime"
        "nodiratime"
        "commit=120"
        "compress=zstd"
        "discard=async"
        "x-systemd.growfs"
      ];
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
    # Cheap, every boot, before tmpfiles: make-btrfs-fs builds / and /nix owned by
    # the build uid (1000); systemd-tmpfiles refuses to operate under non-root
    # parents ("unsafe path transition", fatal at login), so re-own the top dirs.
    systemd.services.fix-sd-root-ownership = {
      description = "Re-own / and /nix to root (make-btrfs-fs builds them uid 1000)";
      wantedBy = [ "sysinit.target" ];
      after = [ "systemd-remount-fs.service" ];
      before = [ "systemd-tmpfiles-setup.service" ];
      unitConfig.DefaultDependencies = false;
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "-${pkgs.coreutils}/bin/chown 0:0 / /nix";
      };
    };

    # One-time: make-btrfs-fs also builds every /nix/store *path* as uid 1000,
    # which trips owner checks (e.g. logrotate refuses non-root configs). The
    # store is a read-only bind mount, so chowning it directly fails; reach the
    # underlying inodes through a fresh read-write bind of / (which does not carry
    # the store's ro sub-mount), recursively re-own, then drop the bind. Gated by a
    # marker so the slow walk is paid once (nix-daemon-added paths are already
    # root). Kept off the early-boot path with no start timeout so it can't be
    # killed mid-walk; re-checks logrotate once done so the deploy comes out clean.
    systemd.services.reroot-nix-store = {
      description = "One-time re-own of make-btrfs-fs /nix/store contents to root";
      wantedBy = [ "multi-user.target" ];
      # Ordered before owner-sensitive consumers so they see the re-owned store on
      # first boot. NB: do NOT add an ExecStartPost that restarts an ordered-after
      # unit (e.g. logrotate-checkconf) synchronously — that's a deadlock (the
      # restart blocks until that unit starts, which can't until this one finishes).
      before = [ "logrotate-checkconf.service" ];
      unitConfig.ConditionPathExists = "!/var/lib/nixos/.sd-store-rerooted";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        TimeoutStartSec = 0;
        ExecStart = pkgs.writeShellScript "reroot-nix-store" ''
          b=/run/sd-reroot
          ${pkgs.coreutils}/bin/mkdir -p "$b"
          if ${pkgs.util-linux}/bin/mount --bind / "$b" 2>/dev/null; then
            ${pkgs.coreutils}/bin/chown -R 0:0 "$b/nix" 2>/dev/null || true
            ${pkgs.util-linux}/bin/umount "$b" 2>/dev/null || true
          fi
          ${pkgs.coreutils}/bin/rmdir "$b" 2>/dev/null || true
          ${pkgs.coreutils}/bin/mkdir -p /var/lib/nixos
          ${pkgs.coreutils}/bin/touch /var/lib/nixos/.sd-store-rerooted
        '';
      };
    };

    # Grow the btrfs root to fill its partition. growPartition (above) extends
    # the PARTITION on boot, but `x-systemd.growfs` doesn't reliably grow a btrfs
    # ROOT here (observed: partition at full 58G, fs stuck at the image's ~5G).
    # Do it explicitly — `resize max` is idempotent (a no-op once full), so this
    # is safe on every boot and survives the partition being grown a boot later.
    systemd.services.grow-btrfs-root = {
      description = "Grow btrfs / to fill its partition";
      wantedBy = [ "multi-user.target" ];
      after = [ "growpart.service" "local-fs.target" ];
      unitConfig.ConditionPathIsMountPoint = "/";
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStart = "${pkgs.btrfs-progs}/bin/btrfs filesystem resize max /";
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
      # The FAT firmware partition is populated separately (populateFirmwareCommands)
      # and must not be a *required* mount during the image build. BUT the system
      # that boots from the flashed image IS this toplevel, so it still needs the
      # real root mount OPTIONS (compress/noatime/x-systemd.growfs) and a writable
      # /boot for kernel updates. Keep both — just mark /boot `nofail` so neither
      # the build nor an early boot blocks on it. (A bare options-less mkForce here
      # was leaking into the booted system: stripped root options + unmounted /boot.)
      fileSystems = lib.mkForce {
        "/" = {
          device = "/dev/disk/by-label/NIXOS_SD";
          fsType = "btrfs";
          # MUST mirror the runtime module's root options above.
          options = [
            "noatime"
            "nodiratime"
            "commit=120"
            "compress=zstd"
            "discard=async"
            "x-systemd.growfs"
          ];
        };
        "/boot" = {
          device = "/dev/disk/by-label/FIRMWARE";
          fsType = "vfat";
          options = [ "nofail" ];
        };
      };
    };
}
