# Samsung Galaxy S7 (herolte, Exynos 8890) — Mobile NixOS device port.
#
# Headless edge-server target (no telephony/UI work). Hardware enablement and
# boot parameters mirror the postmarketOS port (pmaports device/testing/
# {device,linux,firmware}-samsung-herolte*): downstream 3.18 kernel from
# 8890q (Ivan Meler's universal8890 tree, also used by LineageOS builds),
# Android boot.img flashed with heimdall to the BOOT partition, rootfs on
# USERDATA. The DTB is packed into a Samsung DTBH dt.img by dtbTool-exynos
# (handled by mobile-nixos' kernel-builder isExynosDT) and referenced via
# mkbootimg --dt.
#
# Targets SM-G930F/FD (eur_open DTB revisions 04/08/09 built by the kernel
# package). Korean (G930S/K/L) and US (G930A/P/T/V) variants are untested.
{ config, lib, pkgs, ... }:

let
  inherit (lib) mkDefault mkOption types;
in
{
  # hardware-soc.nix asserts the soc exists under mobile.hardware.socs;
  # mobile-nixos only knows exynos-7880, so declare ours here.
  options.mobile.hardware.socs.exynos-8890.enable = mkOption {
    type = types.bool;
    default = false;
    description = "enable when SOC is Exynos 8890";
  };

  config = {
    mobile.device.name = "samsung-herolte";
    mobile.device.identity = {
      name = "Galaxy S7";
      manufacturer = "Samsung";
    };
    mobile.device.supportLevel = "best-effort";

    mobile.hardware = {
      soc = "exynos-8890";
      ram = 1024 * 4;
      screen = {
        width = 1440;
        height = 2560;
      };
    };

    mobile.system.type = "android";
    mobile.system.system = "aarch64-linux";
    mobile.system.android = {
      device_name = "herolte";
      flashingMethod = "odin";
      # Stock Samsung PIT labels (verify with `heimdall print-pit`).
      boot_partition_destination = "BOOT";
      # Rootfs goes to USERDATA, not SYSTEM: SYSTEM is only ~4 GB, far too
      # small for a NixOS store. Stage-1 finds the rootfs by filesystem
      # label, not partition, so this Just Works.
      system_partition_destination = "USERDATA";

      # From pmOS device-samsung-herolte deviceinfo.
      bootimg.flash = {
        offset_base    = "0x10000000";
        offset_kernel  = "0x00008000";
        offset_ramdisk = "0x01000000";
        offset_second  = "0x00f00000";
        offset_tags    = "0x00000100";
        pagesize       = "2048";
      };
      # Samsung DTBH multi-rev dt.img produced by the kernel build.
      bootimg.dt = "${config.mobile.boot.stage-1.kernel.package}/dt.img";
    };

    mobile.boot.stage-1.kernel = {
      package = pkgs.callPackage ./kernel { };
      # The pmOS defconfig has CONFIG_MODULES disabled and the BCM4359 dhd
      # driver builtin — fully monolithic.
      modular = false;
    };

    # The BOOT partition is 64M; xz keeps the kernel+initrd comfortably under.
    mobile.boot.stage-1.compression = mkDefault "xz";

    # BCM4359 WiFi/BT firmware (unfree, fetched from TheMuppets vendor tree).
    mobile.device.firmware = pkgs.callPackage ./firmware { };
    mobile.device.enableFirmware = true;

    # The downstream kernel has no ConfigFS gadget (USB_CONFIGFS unset), only
    # the legacy android_usb composite gadget (USB_G_ANDROID=y).
    mobile.usb = {
      mode = "android_usb";
      # Samsung vendor id; product id picked not to collide with
      # download-mode (685D) or stock MTP/ADB compositions.
      idVendor = "04E8";
      idProduct = "6863";
    };

    mobile.kernel.structuredConfig = [
      (helpers: with helpers; {
        ARCH_EXYNOS = mkDefault yes;
        # Headless server: no use for the secure camera/IR ISP blocks.
      })
    ];
  };
}
