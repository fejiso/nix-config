# Downstream 3.4 kernel for the Kindle Fire HDX 7 (thor), from the
# kernel_phoenix_hdx-common tree @ the exact commit pmOS packages. NOTE: the
# original ggow repo vanished from GitHub; KillzoneCHS' fork contains the
# identical commit (verified by SHA). Config + patches vendored verbatim from
# pmaports device/testing/linux-amazon-thor.
#
# WIP: 3.4-era C vs gcc-15 will need more patches (or kernel-builder-clang /
# a pinned old gcc). Not yet compile-tested.
{ mobile-nixos
, fetchFromGitHub
, ...
}:

mobile-nixos.kernel-builder {
  version = "3.4.113";
  configfile = ./config.armv7l;

  src = fetchFromGitHub {
    owner = "KillzoneCHS";
    repo = "kernel_phoenix_hdx-common";
    rev = "f73e4eec8717c6104eca954cf9c259d9d37c38a5";
    hash = "sha256-qQx5uRZM9whLCwO36kkHaHzBDW7lc8kVoEcTVit0c9U=";
  };

  patches = [
    ./00_Input-lifebook-use-static-inline-instead-of-inline-i.patch
    ./00_Input-sentelic-use-static-inline-instead-of-inline.patch
    ./00_fix_qaudio.patch
    ./00_fix_return_address.patch
    ./00_fix_smd_private.patch
    ./02_gpu-msm-fix-gcc5-compile.patch
    ./03_msm_fix_trace.patch
    ./06_fix_mdss_fb_rgb_mode.patch
    ./gcc10-extern_YYLOC_global_declaration.patch
  ];

  # The tree ships its own yylloc patch; the builder's default would conflict.
  enableDefaultYYLOCPatch = false;

  # QCDT dt.img (dtbTool) referenced via mkbootimg --dt.
  isQcdt = true;
  isModular = true;
}
