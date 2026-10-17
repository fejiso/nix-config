# Downstream 3.18 kernel for the Galaxy S7 (herolte), from 8890q's
# universal8890 tree (the same source postmarketOS' linux-samsung-herolte and
# Ivan Meler's LineageOS builds use). The full config is vendored verbatim
# from pmaports (config-samsung-herolte.aarch64, itself based on
# exynos8890-hero2lte_defconfig) plus pmOS' two patches:
#   01: Mali kbase kstrtobool_from_user build fix
#   02: point the BCM4359 dhd driver at /lib/firmware/postmarketos
# mobile-nixos' kernel-config module layers NixOS/systemd requirements on top
# via structuredConfig.
#
# exynos_platform/subtype are the kernel-builder defaults (0x50a6/0x217584da),
# matching pmOS' dtbTool-exynos invocation; dt.img lands in $out/dt.img.
{ mobile-nixos
, fetchFromGitHub
, ...
}:

mobile-nixos.kernel-builder {
  version = "3.18.140";
  configfile = ./config.aarch64;

  src = fetchFromGitHub {
    owner = "8890q";
    repo = "android_kernel_samsung_universal8890";
    rev = "57884d864fb572642fcf84abf13b099db7efc5b8";
    hash = "sha256-1vipxgEtbiS1HbR6//4Rh8+/jgUfohI+gWCJXffLlr8=";
  };

  patches = [
    ./01-kstrtobool_from_user.patch
    ./02-fix-wifi-firmware-path.patch
    ./03-binutils-section-syntax.patch
  ];

  # Samsung DTBH multi-DTB image (eur_open revisions) for mkbootimg --dt.
  isExynosDT = true;

  # pmOS config: CONFIG_MODULES is not set; everything (incl. the dhd WiFi
  # driver) is builtin.
  isModular = false;

  # The kernel-builder's default yylloc multiple-definition patch is already
  # upstream in this 3.18 tree (applies reversed); skip it.
  enableDefaultYYLOCPatch = false;

  # 3.18's arm64 Makefile predates the `dtbs_install` target (the DTBs
  # themselves build fine — `make dtbs` works). Provide a minimal one so the
  # kernel-builder's `make dtbs dtbs_install` succeeds.
  postPatch = ''
    {
      echo  # the file has no trailing newline; don't glue onto the last line
      echo 'PHONY += dtbs_install'
      echo 'dtbs_install: dtbs'
      printf '\tmkdir -p $(INSTALL_DTBS_PATH)\n'
      printf '\tcp arch/arm64/boot/dts/*.dtb $(INSTALL_DTBS_PATH)/\n'
    } >> arch/arm64/Makefile
  '';
}

# mobile-nixos' NixOS integration uses `system.boot.loader.kernelFile`, which
# defaults to the kernel's `file` attribute. The builder exposes `target`
# (`Image.gz` here) but not `file`, so the system builder looks for the
# uncompressed `Image` and fails. Tell it where the compressed image is.
// { file = "Image.gz"; }
