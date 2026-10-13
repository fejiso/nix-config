# Downstream 4.9 kernel for the Kindle Fire 7 2019 (mustang), @ the exact
# commit pmOS packages. NOTE: the original ggow repo vanished from GitHub;
# the mt8163 org's repo contains the identical commit (verified by SHA).
# Config + patches vendored verbatim from pmaports
# device/testing/linux-amazon-mustang.
#
# The DTB is appended at kernel build time (CONFIG_BUILD_ARM_APPENDED_DTB_IMAGE
# with mustang_proto/mustang_hvt) → the bootable image is zImage-dtb.
# WIP: not yet compile-tested with a modern toolchain.
{ mobile-nixos
, fetchFromGitHub
, ...
}:

mobile-nixos.kernel-builder {
  version = "4.9.77";
  configfile = ./config.armv7l;

  src = fetchFromGitHub {
    owner = "mt8163";
    repo = "android_kernel_amazon_mustang";
    rev = "42d97d6450e8ba87315543081a765b0f0a1da358";
    hash = "sha256-Eht1hlrTxhFx8j+Ls4myfXrFAKGjQytoOhxGtGEaDO8=";
  };

  patches = [
    ./linux4.2-gcc10-extern_YYLOC_global_declaration.patch
    ./pinctrl-mtk-common.patch
  ];

  # The tree ships its own yylloc patch; the builder's default would conflict.
  enableDefaultYYLOCPatch = false;

  target = "zImage-dtb";  # CONFIG_BUILD_ARM_APPENDED_DTB_IMAGE
  isCompressed = false;
  isModular = true;
}
