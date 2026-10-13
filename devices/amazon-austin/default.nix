# Amazon Kindle Fire 7 (2017, "austin", MediaTek MT8127) — Mobile NixOS device port.
#
# *** WIP / NOT USABLE AS A WIFI SERVER ***
# - No official bootloader unlock: requires the amonet MT8127 bootrom exploit.
# - WiFi uses MediaTek's proprietary consys driver; firmware blobs must be
#   sourced from the stock OS (pmaports ships no firmware package).
# - Legacy ATAGS kernel (no device tree); pmOS builds it with gcc4 — expect
#   heavy compile iteration with a modern toolchain.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  config = {
    mobile.device.name = "amazon-austin";
    mobile.device.identity = {
      name = "Kindle Fire 7 (2017)";
      manufacturer = "Amazon";
    };
    mobile.device.supportLevel = "broken";

    mobile.hardware = {
      soc = "mediatek-mt8127";
      ram = 1024;
      screen = {
        width = 600;
        height = 1024;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "armv7l-linux";
    mobile.system.android = {
      device_name = "austin";
      flashingMethod = "fastboot";
      boot_partition_destination = "boot";
      system_partition_destination = "userdata";

      bootimg.flash = {
        offset_base    = "0x80000000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x04000000";
        offset_second  = "0x00f00000";
        offset_tags    = "0x00000100";
        pagesize       = "2048";
      };
    };

    # From deviceinfo_kernel_cmdline (kept verbatim; ipv6.disable=1 is pmOS'
    # choice for this kernel — drop it if IPv6 is needed).
    boot.kernelParams = [
      "bootopt=64S3,32N2,32N2"
      "loglevel=4"
      "rootwait"
      "ro"
      "fsck.repair=yes"
      "net.ifnames=0"
      "ipv6.disable=1"
    ];

    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      modular = true;
    };
    mobile.boot.stage-1.compression = mkDefault "xz";

    mobile.device.enableFirmware = false;

    # USB gadget state on the MTK 3.10 tree is unknown (no ConfigFS);
    # leave the gadget unconfigured until bring-up.
    mobile.usb.mode = null;
  };
}
