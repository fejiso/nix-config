# Amazon Kindle Fire HDX 7 (thor, Qualcomm MSM8974) — Mobile NixOS device port.
#
# *** WIP / NOT USABLE AS A WIFI SERVER ***
# - Bootloader unlock requires the HDX-specific aboot exploit (downgrade to
#   Fire OS 13.3.2.4 first — NOT amonet).
# - The downstream 3.4 kernel config pmOS ships has NO WLAN driver enabled at
#   all; WiFi needs driver work first.
# - pmOS builds the QCDT dt.img with `dtbTool --version=1`; mobile-nixos'
#   kernel-builder doesn't pass that flag (known mismatch, fix at bring-up).
# - Kernel is gcc-4/5-era C; expect compile iteration (or kernel-builder-clang
#   / a pinned older gcc) before it builds with a modern toolchain.
#
# Facts from pmaports device/testing/{device,linux}-amazon-thor.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  options.mobile.hardware.socs.qcom-msm8974-downstream.enable = mkOption {
    type = types.bool;
    default = false;
    description = "enable when SOC is Qualcomm MSM8974 (downstream kernel)";
  };

  config = {
    mobile.device.name = "amazon-thor";
    mobile.device.identity = {
      name = "Kindle Fire HDX 7";
      manufacturer = "Amazon";
    };
    mobile.device.supportLevel = "broken";

    mobile.hardware = {
      soc = "qcom-msm8974-downstream";
      ram = 1024 * 2;
      screen = {
        width = 1200;
        height = 1920;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "armv7l-linux";
    mobile.system.android = {
      device_name = "thor";
      flashingMethod = "fastboot";
      boot_partition_destination = "boot";
      system_partition_destination = "userdata";

      bootimg.flash = {
        offset_base    = "0x00000000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x02000000";
        offset_second  = "0x00f00000";
        offset_tags    = "0x01e00000";
        pagesize       = "2048";
      };
      # QCDT dt.img produced by the kernel build (dtbTool).
      bootimg.dt = "${config.mobile.boot.stage-1.kernel.package}/dt.img";
    };

    # From deviceinfo_kernel_cmdline.
    boot.kernelParams = [
      "console=ttyHSL0,115200,n8"
      "androidboot.hardware=qcom"
      "user_debug=31"
      "msm_rtb.filter=0x37"
      "ehci-hcd.park=3"
    ];

    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      modular = true;
    };
    mobile.boot.stage-1.compression = mkDefault "xz";

    # No firmware packaged: pmaports ships none for thor.
    mobile.device.enableFirmware = false;

    # Legacy android_usb gadget (3.4 downstream kernel, no ConfigFS).
    mobile.usb = {
      mode = "android_usb";
      idVendor = "1949";  # Amazon
      idProduct = "4EE7";
    };
  };
}
