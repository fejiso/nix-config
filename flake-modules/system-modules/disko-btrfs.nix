{ inputs, ... }: {
  flake.modules.nixos.disko-btrfs = { config, lib, ... }:
    let
      cfg = config.diskoLayout;
    in
    {
      imports = [ inputs.disko.nixosModules.disko ];

      options.diskoLayout = {
        device = lib.mkOption {
          type = lib.types.str;
          default = "/dev/nvme0n1";
          example = "/dev/sda";
          description = ''
            Primary target block device for disko (`disko.devices.disk.main.device`).
            Can also be overridden ad-hoc at install time via `--disk main /dev/...`.
          '';
        };

        espSize = lib.mkOption {
          type = lib.types.str;
          default = "1G";
          description = "Size of the EFI System Partition mounted at /boot.";
        };

        biosBoot = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = ''
            Add a 1M EF02 BIOS boot partition and switch the bootloader from
            systemd-boot to hybrid BIOS+EFI GRUB (useful for legacy BIOS laptops).
          '';
        };

        swapSize = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = "16G";
          example = "8G";
          description = ''
            Size of the Btrfs swapfile inside the dedicated `@swap` subvolume
            (`/.swapvol/swapfile`), keeping `@` snapshots swapfile-free.
            Set to `null` to omit the `@swap` subvolume and swapfile.
          '';
        };

        resumeOffset = lib.mkOption {
          type = lib.types.nullOr lib.types.int;
          default = null;
          example = 533760;
          description = ''
            Physical swapfile offset for hibernation (`resume_offset` kernel parameter).
            After formatting, obtain with:
              `sudo btrfs inspect-internal map-swapfile -r /.swapvol/swapfile`
          '';
        };
      };

      config = {
        disko.devices.disk.main = {
          type = "disk";
          device = cfg.device;
          content = {
            type = "gpt";
            partitions =
              lib.optionalAttrs cfg.biosBoot {
                boot = {
                  size = "1M";
                  type = "EF02";
                  priority = 1;
                };
              }
              // {
                ESP = {
                  size = cfg.espSize;
                  type = "EF00";
                  content = {
                    type = "filesystem";
                    format = "vfat";
                    mountpoint = "/boot";
                    mountOptions = [ "fmask=0077" "dmask=0077" ];
                  };
                };

                root = {
                  size = "100%";
                  content = {
                    type = "btrfs";
                    # Disable block-group-tree (newly default in btrfs-progs 6.19, requires
                    # kernel >= 6.1) so older Live USB kernels can mount /mnt during install.
                    extraArgs = [ "-f" "-O" "^block-group-tree" ];
                    preCreateHook = ''
                      if [ -d /run/booted-system/kernel-modules ]; then
                        /run/current-system/sw/bin/modprobe -d /run/booted-system/kernel-modules btrfs 2>/dev/null || true
                      else
                        modprobe btrfs 2>/dev/null || true
                      fi
                      wipefs -af "$device" || true
                      dd if=/dev/zero of="$device" bs=1M count=16 conv=notrunc status=none || true
                      dev_mib=$(( $(blockdev --getsize64 "$device") / 1048576 ))
                      if [ "$dev_mib" -gt 32 ]; then
                        dd if=/dev/zero of="$device" bs=1M seek=$(( dev_mib - 16 )) count=16 conv=notrunc status=none || true
                      fi
                      udevadm settle || true
                      mount() { command mount -t btrfs "$@"; }
                    '';
                    preMountHook = ''
                      mount() { command mount -t btrfs "$@"; }
                    '';
                    subvolumes = {
                      "@" = {
                        mountpoint = "/";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                      "@home" = {
                        mountpoint = "/home";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                      "@nix" = {
                        mountpoint = "/nix";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                      "@log" = {
                        mountpoint = "/var/log";
                        mountOptions = [ "compress=zstd" "noatime" ];
                      };
                    } // lib.optionalAttrs (cfg.swapSize != null) {
                      "@swap" = {
                        mountpoint = "/.swapvol";
                        mountOptions = [ "noatime" ];
                        swap.swapfile.size = cfg.swapSize;
                      };
                    };
                  };
                };
              };
          };
        };

        fileSystems."/var/log".neededForBoot = true;

        boot.loader.systemd-boot.enable = lib.mkIf cfg.biosBoot (lib.mkForce false);
        boot.loader.efi.canTouchEfiVariables = lib.mkIf cfg.biosBoot (lib.mkForce false);
        boot.loader.grub = lib.mkIf cfg.biosBoot {
          enable = lib.mkDefault true;
          efiSupport = lib.mkDefault true;
          efiInstallAsRemovable = lib.mkDefault true;
        };

        boot.resumeDevice = lib.mkIf (cfg.resumeOffset != null) "/dev/disk/by-partlabel/disk-main-root";
        boot.kernelParams = lib.mkIf (cfg.resumeOffset != null) [
          "resume_offset=${toString cfg.resumeOffset}"
        ];
      };
    };
}
