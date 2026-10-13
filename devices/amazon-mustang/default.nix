# Amazon Kindle Fire 7 (2019, "mustang", MediaTek MT8163) — Mobile NixOS device port.
#
# *** WIP / NOT USABLE AS A WIFI SERVER ***
# - No official bootloader unlock: requires the kamakiri MT8163 bootrom
#   exploit first.
# - WiFi uses MediaTek's proprietary consys driver; firmware blobs must be
#   sourced from the stock OS (pmaports ships no firmware package).
# - Downstream 4.9 kernel; the most modern of the Kindle ports, so the best
#   candidate of the three Fire 7s to finish first.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  options.mobile.hardware.socs.mediatek-mt8163.enable = mkOption {
    type = types.bool;
    default = false;
    description = "enable when SOC is MediaTek MT8163";
  };

  config = {
    mobile.device.name = "amazon-mustang";
    mobile.device.identity = {
      name = "Kindle Fire 7 (2019)";
      manufacturer = "Amazon";
    };
    mobile.device.supportLevel = "broken";

    mobile.hardware = {
      soc = "mediatek-mt8163";
      ram = 1024;
      screen = {
        width = 600;
        height = 1024;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "armv7l-linux";
    mobile.system.android = {
      device_name = "mustang";
      flashingMethod = "fastboot";
      boot_partition_destination = "boot";
      system_partition_destination = "userdata";

      # Note the unusual base (0x40078000) — standard bootimg otherwise.
      bootimg.flash = {
        offset_base    = "0x40078000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x03408000";
        offset_second  = "0x00e88000";
        offset_tags    = "0x07f88000";
        pagesize       = "2048";
      };
    };

    # From deviceinfo_kernel_cmdline.
    boot.kernelParams = [
      "bootopt=64S3,32N2,64N2"
      "androidboot.selinux=permissive"
      "buildvariant=userdebug"
    ];

    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      modular = true;
    };
    mobile.boot.stage-1.compression = mkDefault "xz";

    mobile.device.enableFirmware = false;

    # USB gadget state on the MTK 4.9 tree is unverified; leave the gadget
    # unconfigured until bring-up.
    mobile.usb.mode = null;
  };
}
