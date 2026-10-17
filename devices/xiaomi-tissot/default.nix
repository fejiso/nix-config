# Xiaomi Mi A1 (tissot, Qualcomm MSM8953) — Mobile NixOS device port.
#
# aarch64, close-to-mainline kernel (msm8953-mainline). Boots via lk2nd:
# lk2nd-msm8953 is flashed to the boot partition once (stock fastboot), after
# which lk2nd's own fastboot flashes the real boot.img. WiFi is a WCN3680
# (wcn36xx): the firmware blobs are NOT redistributable and live in the
# phone's stock modem partition, so they're extracted at runtime (see the
# tissot-wifi-firmware service below) instead of being packaged.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  options.mobile.hardware.socs.qcom-msm8953.enable = mkOption {
    type = types.bool;
    default = false;
    description = "enable when SOC is Qualcomm MSM8953";
  };

  config = {
    mobile.device.name = "xiaomi-tissot";
    mobile.device.identity = {
      name = "Mi A1";
      manufacturer = "Xiaomi";
    };
    mobile.device.supportLevel = "best-effort";

    mobile.hardware = {
      soc = "qcom-msm8953";
      ram = 1024 * 4;
      screen = {
        width = 1080;
        height = 1920;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "aarch64-linux";
    mobile.system.android = {
      device_name = "tissot";
      flashingMethod = "lk2nd";
      boot_partition_destination = "boot";
      system_partition_destination = "userdata";

      # From pmOS device-xiaomi-tissot deviceinfo.
      bootimg.flash = {
        offset_base    = "0x80000000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x01000000";
        offset_second  = "0x00f00000";
        offset_tags    = "0x00000100";
        pagesize       = "2048";
      };
      appendDTB = [ "dtbs/qcom/msm8953-xiaomi-tissot.dtb" ];
    };

    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      modular = true;
    };
    mobile.boot.stage-1.compression = mkDefault "xz";

    # The NixOS closure is far larger than mobile-nixos' default 20 MiB padding.
    # Add headroom so the ext4 rootfs image has enough inodes/blocks.
    # Wrapped in mkDefault/mkForce so it merges with rootfs.nix' defaults.
    mobile.generatedFilesystems.rootfs = lib.mkDefault {
      extraPadding = lib.mkForce (pkgs.image-builder.helpers.size.GiB 1);
    };

    # Mainline kernel: ConfigFS gadget with RNDIS for USB networking.
    mobile.usb = {
      mode = "gadgetfs";
      idVendor = "2717";  # Xiaomi
      idProduct = "4EE7"; # not a stock value — distinguish from fastboot/lk2nd
      gadgetfs.functions = {
        rndis = "rndis.usb0";
      };
    };

    # WCN3680 WiFi firmware lives in the stock modem partition. Make the
    # runtime extraction dir a firmware search path, keep wcn36xx from
    # probing before the blobs are there, then probe it manually.
    boot.kernelParams = [ "firmware_class.path=/run/modem-fw" ];
    boot.blacklistedKernelModules = [ "wcn36xx" ];
    systemd.services.tissot-wifi-firmware = {
      description = "Extract WCN3680 WiFi firmware from the stock modem partition";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      path = with pkgs; [ util-linux kmod coreutils gnugrep ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        set -e
        mkdir -p /run/modem-fw /tmp/modem
        if mount -o ro /dev/disk/by-partlabel/modem /tmp/modem 2>/dev/null; then
          cp -r /tmp/modem/image/* /run/modem-fw/ 2>/dev/null || true
          umount /tmp/modem
        else
          echo "tissot-wifi-firmware: no modem partition found (stock layout wiped?) — WiFi unavailable"
        fi
        modprobe wcn36xx || echo "tissot-wifi-firmware: wcn36xx probe failed"
      '';
    };

    mobile.kernel.structuredConfig = [
      (helpers: with helpers; {
        ARCH_QCOM = mkDefault yes;

        # The vendored pmOS config has CONFIG_IPV6=m. Mobile NixOS requires
        # the netfilter/nftables chain *builtin* (=y), and kconfig clamps any
        # =y that depends on an =m symbol back to =m — with IPV6 as a module,
        # all 17 of them (BRIDGE, NFT_*, IP6_NF_*, XT_MATCH_*) fail config
        # validation. Build IPV6 and the tproxy/socket parents in.
        IPV6 = yes;
        # (NF_TPROXY itself is promptless — selected by NFT_TPROXY — so it
        # must not be pinned here; oldconfig drops user values for it.)
        NF_SOCKET_IPV4 = yes;
        NF_SOCKET_IPV6 = yes;
      })
    ];
  };
}
