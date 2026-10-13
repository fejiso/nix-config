# Amazon Kindle Fire 7 (2015, "ford", MediaTek MT8127) — Mobile NixOS device port.
#
# *** WIP / NOT USABLE AS A WIFI SERVER ***
# - No official bootloader unlock: requires the amonet MT8127 bootrom exploit
#   first (shorting test points / software trigger, see the amonet-mt8127 docs).
# - WiFi uses MediaTek's proprietary consys driver; firmware blobs must be
#   sourced from the stock OS (pmaports ships no firmware package).
# - Legacy ATAGS kernel (no device tree at all): 3.10 board-file C, gcc-4-era;
#   expect compile iteration with a modern toolchain.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  config = {
    mobile.device.name = "amazon-ford";
    mobile.device.identity = {
      name = "Kindle Fire 7 (2015)";
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
      device_name = "ford";
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

    # From deviceinfo_kernel_cmdline.
    boot.kernelParams = [
      "androidboot.selinux=permissive"
      "androidboot.hardware=mt8127"
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
