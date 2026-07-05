{ lib, pkgs, ... }:

{
  # 64-bit ARM (Xilinx Zynq UltraScale+ ZU2EG, Cortex-A53). Cross-compile: build
  # on x86, target aarch64. Pure cross (no QEMU binfmt), so everything is
  # produced as ordinary x86 derivations emitting aarch64 output — same model as
  # z-turn (the repo routes aarch64 via amp1 OR cross; kr260 picks cross).
  nixpkgs.hostPlatform  = lib.mkDefault "aarch64-linux";
  nixpkgs.buildPlatform = lib.mkDefault "x86_64-linux";

  # linux-xlnx (Xilinx fork, ZynqMP) — overrides the sd-image module's
  # linuxPackages_latest.
  boot.kernelPackages = lib.mkForce (pkgs.linuxPackagesFor pkgs.linuxZynqmpXlnx);

  # The SD-image profile pulls in nixos all-hardware.nix, whose broad
  # availableKernelModules list (Allwinner pwm-sun4i, etc.) isn't in the ZynqMP
  # xlnx kernel and breaks modules-shrunk. The board's MMC/SDHCI/btrfs drivers
  # are builtin, so no initrd device modules are needed.
  boot.initrd.availableKernelModules = lib.mkForce [ ];

  hardware.deviceTree = {
    enable = true;
    # KR260 revB (board silkscreen "REV B01"; u-boot reports "Model: ZynqMP KR260
    # revB", FRU SOM "SMK-K26-XCL2G rev1" + carrier "SCK-KR-G rev1"). linux-xlnx's
    # DT naming predates the "rev1" FRU labels: it has only `smk-k26-revA` SOMs
    # (no revB SOM in this tree) with carrier `sck-kr-g-revA`/`-revB`. So: SOM
    # revA, carrier revB. (Verified present in the built kernel's dtbs/.)
    name = "xilinx/zynqmp-smk-k26-revA-sck-kr-g-revB.dtb";
    # The K26 SOM DTS (zynqmp-sm-k26-revA.dts:107) ships a `pwm-fan` node on
    # ttc0 ch2, but never pins the TTC's PWM wave output to a physical pad — so
    # the PWM is internal-only and the KR260 blower is hardwired to full speed.
    # Verified: writing pwm1 / toggling pwm1_enable has no effect (debugfs duty
    # tracks 157->39999 ns, fan unchanged); the SCK-KR-G carrier DTS has no fan
    # path either (no GPIO/I2C controller). Disable the inert node so it stops
    # exposing a dead `pwmfan` hwmon and inviting more unworkable fan-control
    # code. Real fan control would need a carrier-schematic-informed hardware
    # path (TTC pinctrl + carrier wiring, or a PL PWM bitstream).
    overlays = [ {
      name = "disable-pwm-fan";
      dtsText = ''
        /dts-v1/;
        /plugin/;
        / {
          compatible = "xlnx,zynqmp-sk-kr260";
          fragment@0 {
            target-path = "/pwm-fan";
            __overlay__ { status = "disabled"; };
          };
        };
      '';
    } ];
  };

  # USB stability fix (root cause of the btrfs read-error storm). The card boots
  # through the on-board Microchip USB2744 hub → USB card reader (root shows up
  # as /dev/sda2, NOT mmcblk). The `onboard-usb-dev` driver (CONFIG_USB_ONBOARD_DEV)
  # binds to those hub nodes, can't find their regulators ("supply vdd not found,
  # using dummy regulator"), and immediately power-cycles the hubs — which
  # disconnects the card reader mid-transfer. The dmesg timestamping is exact:
  # `onboard-usb-dev` registers → `usb 1-1: USB disconnect` → `BTRFS error sda2
  # errs: rd 1, 2, 3…`. Two known-good cards fail identically because the fault
  # is the hub reset, not the media. The hubs are self-powered standard USB
  # hubs and need no onboard-usb-dev power sequencing, so just suppress that
  # driver. It's =m (module loaded by udev), so blacklistedKernelModules is the
  # real fix; initcall_blacklist is belt-and-suspenders in case it's ever built
  # in. (Card via native sdhci1 / 1.8V SDR104 is a different board's issue — the
  # KR260's card is behind USB here.)
  boot.blacklistedKernelModules = [ "onboard_usb_dev" "onboard-usb-dev" ];
  boot.kernelParams = [ "initcall_blacklist=onboard_dev_init" ];

  # Root filesystem (btrfs) and the FAT boot partition come from the shared
  # sd-image-btrfs module (wired in by mk-host for sdImage hosts).

  swapDevices = [ ];
  networking.useDHCP = lib.mkDefault true;
}
