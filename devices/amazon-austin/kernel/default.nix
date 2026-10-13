# Downstream 3.10 kernel for the Kindle Fire 7 2017 (austin): Amazon's own
# stock source drop (hexdump0815 mirror, tag Fire_7_7th_Gen-5.3.7.3) @ the
# exact ref pmOS packages. Config + patches vendored verbatim from pmaports
# device/testing/linux-amazon-austin (the silence-* patches just quiet log
# spam; keep them — on a serial-less tablet the console IS the display).
#
# Legacy ATAGS board-file kernel: no device tree (buildDTBs off).
# WIP: pmOS builds this with gcc4; expect heavy iteration with a modern
# toolchain (start with kernel-builder-clang or a pinned old gcc).
{ mobile-nixos
, fetchFromGitHub
, ...
}:

mobile-nixos.kernel-builder {
  version = "3.10.54";
  configfile = ./config.armv7l;

  src = fetchFromGitHub {
    owner = "hexdump0815";
    repo = "linux-amazon-mediatek-mt8127-kernel-source";
    rev = "Fire_7_7th_Gen-5.3.7.3-20210714";
    hash = "sha256-suQrK6sgLaDr0oWUXHk8MZEFI4jYSQciwmZ7LL7CQIA=";
  };

  patches = [
    ./fix-host-card-inserted.patch
    ./gcc4-compile-fixes.patch
    ./silence-battery-logspam.patch
    ./silence-cmb-logspam.patch
    ./silence-hotplug-logspam.patch
    ./silence-i2c-logspam.patch
    ./silence-mtkfb-logspam.patch
    ./silence-power-logspam.patch
    ./silence-thermal-logspam.patch
    ./silence-time-logspam.patch
    ./silence-tz-logspam.patch
    ./silence-uart-logspam.patch
    ./silence-usb-logspam.patch
    ./silence-vsync-logspam.patch
  ];

  buildDTBs = false;  # ATAGS kernel, no device tree
  isModular = true;
}
