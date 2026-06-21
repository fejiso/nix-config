{ ... }: {
  flake.modules.nixos.embedded =
{ config, lib, pkgs, ... }:

{
  options.embedded = {
    enable = lib.mkEnableOption "embedded/ARM optimizations for resource-constrained devices";

    serialConsole = lib.mkOption {
      type = lib.types.str;
      default = "ttyS0";
      description = "Serial console device (e.g., ttyS0 for Pine64, ttyAMA0 for RPi)";
    };
  };

  config = lib.mkIf config.embedded.enable {
    # Slim system package set for cross-compiled / resource-constrained ARM.
    #
    # We use mkForce to drop packages the shared base/desktop modules add that
    # don't belong here — notably `fish` (does NOT cross-compile: its native
    # `xtask` build helper links the target's pcre2) and `mpv`/wine (x86 or
    # heavy media). BUT mkForce replaces the ENTIRE list, which would also wipe:
    #   - NixOS' requiredPackages (coreutils, findutils, procps, util-linux, …)
    #     → no `ls`/`find`/`top` in the user PATH;
    #   - `nix` itself → no `nix`/`nix-shell`;
    #   - the user login shells NixOS auto-adds (`systemShells`) → the passwd
    #     shell path /run/current-system/sw/bin/<shell> doesn't exist, so login
    #     dies with "Cannot execute …/bash: No such file or directory".
    # So re-include all of that explicitly here.
    environment.systemPackages =
      lib.mkForce (
        # Configured user login shells (same filter NixOS' systemShells uses).
        (lib.filter lib.types.shellPackage.check
          (lib.unique (lib.mapAttrsToList (_: u: u.shell) config.users.users)))
        ++ [ config.nix.package ] # nix, nix-shell, nix-store, …
        ++ (with pkgs; [
          # Core base userland (NixOS requiredPackages that mkForce would drop).
          coreutils-full findutils diffutils gnugrep gnused gawk
          gnutar gzip bzip2 xz zstd
          util-linux procps less which iproute2
          # Embedded conveniences.
          vim wget curl git htop btop tree unzip ripgrep fd fzf
          tmux screen file pciutils usbutils
        ])
      );

    # Optimize memory usage with zram
    # Override common config which uses lzo
    zramSwap = {
      enable = true;
      algorithm = lib.mkForce "zstd";
      memoryPercent = lib.mkForce 50;  # Higher percentage for limited RAM devices
    };

    # Serial console configuration
    boot.kernelParams = [
      "console=${config.embedded.serialConsole},115200n8"
      "console=tty1"  # Also enable virtual console
    ];

    # Disable unnecessary hardware support by default
    hardware.graphics.enable = lib.mkDefault false;
    hardware.graphics.enable32Bit = lib.mkForce false;  # Not supported on ARM
    hardware.bluetooth.enable = lib.mkDefault true;

    # Disable ZFS (not needed on embedded, may be broken on latest kernels)
    boot.supportedFilesystems = lib.mkForce [ "btrfs" "ext4" "vfat" "f2fs" "xfs" "ntfs" "cifs" "nfs" ];

    # Reduce systemd overhead
    systemd.services.systemd-udev-settle.enable = false;

    # Optimize journald for limited storage
    services.journald.extraConfig = ''
      Storage=volatile
      RuntimeMaxUse=30M
    '';

    # Enable fstrim for SD card longevity (if supported)
    services.fstrim.enable = lib.mkDefault true;

    # Clean /tmp on boot to save space
    boot.tmp.cleanOnBoot = true;

    # --- Trim the inherited fleet server stack (flake.modules.nixos.default) ---
    # A resource-constrained board (e.g. 1 GiB Zynq) shouldn't run mesh routers,
    # seismic relays, audio, etc. Disabling the resident daemons reclaims the
    # bulk of RAM. Kept on purpose: iperf3, storagebox (CIFS), nfs.
    services.i2pd.enable = lib.mkForce false; # I2P router (~50-80 MiB)
    services.yggdrasil.enable = lib.mkForce false; # mesh VPN — netbird covers mesh
    services.microsocks.enable = lib.mkForce false; # SOCKS proxy
    services.automatic-timezoned.enable = lib.mkForce false; # geoclue timezone
    services.pipewire.enable = lib.mkForce false; # audio: headless
    services.avahi.enable = lib.mkForce false; # mDNS

    # Seismic SeedLink relays (7 network daemons) — a board is not a seismic node.
    # These are raw systemd.services (no high-level enable option), so clear their
    # wantedBy to keep them out of multi-user.target (enable=false only masks).
    systemd.services."seedlink-relay-iris".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-geofon".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-resif".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-bgr".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-geonet".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-ipgp".wantedBy = lib.mkForce [ ];
    systemd.services."seedlink-relay-orfeus".wantedBy = lib.mkForce [ ];

    # Reticulum daemons (rnsd/lxmd): mkForce {} (not just wantedBy) because their
    # ExecStart references python3Packages.rns, whose deps (esptool) don't
    # cross-compile — so the reference itself must be dropped from the closure.
    systemd.services.rnsd = lib.mkForce { };
    systemd.services.lxmd = lib.mkForce { };

    # NetworkManager (~25 MiB) -> systemd-networkd, DHCP on the wired NIC.
    # NOTE: this drops WiFi (no NM); a WiFi embedded host must re-enable
    # NetworkManager (mkForce) or configure wpa_supplicant + networkd itself.
    networking.networkmanager.enable = lib.mkForce false;
    networking.useNetworkd = lib.mkDefault true;
    services.resolved.enable = lib.mkDefault true;
    systemd.network.networks."10-embedded-wired" = {
      matchConfig.Name = "en* eth*";
      networkConfig.DHCP = "yes";
      linkConfig.RequiredForOnline = "routable";
    };

    # Override GC to keep 30d on embedded (more conservative)
    systemd.services.nix-garbage-collect.script = lib.mkForce ''
      echo "=== Nix GC start (embedded) ==="
      echo "Store size before: $(du -sh /nix/store | cut -f1)"
      nix-collect-garbage --delete-older-than 30d
      echo "Store size after: $(du -sh /nix/store | cut -f1)"
      echo "=== Nix GC done ==="
    '';

    # Optimize Nix builds on embedded devices
    nix.settings = {
      max-jobs = lib.mkDefault 2;  # Limit parallel builds
      cores = lib.mkDefault 2;     # Limit cores per build
    };
  };
}
;
}
