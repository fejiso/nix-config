# LG Nexus 5 (hammerhead, Qualcomm MSM8974) — Mobile NixOS device port.
#
# armv7l (32-bit) — cross-compiled from x86 like the z-turn (no armv7l binary
# cache). Unlike the other phones here this runs a close-to-mainline kernel
# (msm8974-mainline), so long-term maintainability is good. WiFi is a
# Broadcom BCM4339 over SDIO driven by mainline brcmfmac; only the NVRAM
# calibration text is proprietary (vendored here from pmaports), the .bin
# comes from linux-firmware.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  options.mobile.hardware.socs.qcom-msm8974.enable = mkOption {
    type = types.bool;
    default = false;
    description = "enable when SOC is Qualcomm MSM8974";
  };

  config = {
    mobile.device.name = "lg-hammerhead";
    mobile.device.identity = {
      name = "Nexus 5";
      manufacturer = "LG";
    };
    mobile.device.supportLevel = "best-effort";

    mobile.hardware = {
      soc = "qcom-msm8974";
      ram = 1024 * 2;
      screen = {
        width = 1080;
        height = 1920;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "armv7l-linux";
    mobile.system.android = {
      device_name = "hammerhead";
      flashingMethod = "fastboot";
      boot_partition_destination = "boot";
      system_partition_destination = "userdata";

      # From pmOS device-lg-hammerhead deviceinfo.
      bootimg.flash = {
        offset_base    = "0x00000000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x02900000";
        offset_second  = "0x00f00000";
        offset_tags    = "0x02700000";
        pagesize       = "2048";
      };
      # arm32 dtbs_install is flat (no vendor subdir) — verified in the
      # built kernel package.
      appendDTB = [ "dtbs/qcom-msm8974-lge-nexus5-hammerhead.dtb" ];
    };

    # From deviceinfo_kernel_cmdline.
    boot.kernelParams = [
      "console=ttyMSM0,115200,n8"
      "msm.vram=192m"
      "msm.allow_vram_carveout=1"
    ];

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

    # BCM4339 WiFi: NVRAM txt (proprietary, vendored) + .bin from
    # linux-firmware, packed together.
    mobile.device.firmware = pkgs.callPackage ./firmware { };
    mobile.device.enableFirmware = true;

    # Mainline kernel: ConfigFS gadget with RNDIS for USB networking.
    mobile.usb = {
      mode = "gadgetfs";
      idVendor = "18D1";  # Google
      idProduct = "4EE7"; # not "D001" — distinguish from fastboot
      gadgetfs.functions = {
        rndis = "rndis.usb0";
      };
    };

    mobile.kernel.structuredConfig = [
      (helpers: with helpers; {
        ARCH_QCOM = mkDefault yes;
      })
    ];
  };
}
