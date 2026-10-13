# Downstream 3.10 kernel for the Kindle Fire 7 2015 (ford), from the
# cm14-mt8127 tree @ the exact commit pmOS packages. Config + patches vendored
# verbatim from pmaports device/testing/linux-amazon-ford.
#
# Legacy ATAGS board-file kernel: no device tree (buildDTBs off).
# WIP: not yet compile-tested with a modern toolchain.
{ mobile-nixos
, fetchFromGitHub
, ...
}:

mobile-nixos.kernel-builder {
  version = "3.10.54";
  configfile = ./config.armv7l;

  src = fetchFromGitHub {
    owner = "cm14-mt8127";
    repo = "kernel_amazon_mt8127-common";
    rev = "e53c86b915bed7e5455949277c31b700177df26b";
    hash = "sha256-vqSEe5XJqBu9IGs35qjS79GP0Oa5sgmdCUEx+TFDgms=";
  };

  patches = [
    ./gcc10-extern_YYLOC_global_declaration.patch
    ./gcc8-fix-put-user.patch
  ];

  # The tree ships its own yylloc patch; the builder's default would conflict.
  enableDefaultYYLOCPatch = false;

  buildDTBs = false;  # ATAGS kernel, no device tree
  isModular = true;
}
