# Non-free BCM4359 WiFi firmware for the Galaxy S7/S7 edge (hero family),
# from TheMuppets' LineageOS vendor blob mirror — the same files postmarketOS'
# firmware-samsung-hero package ships. Installed under
# /lib/firmware/postmarketos, which the kernel's dhd driver is patched to use
# (see ../kernel/02-fix-wifi-firmware-path.patch). Both the _c0 suffixed names
# (chip-revision variant pmOS ships) and the bare names (what
# CONFIG_BCMDHD_FW_PATH/CONFIG_BCMDHD_NVRAM_PATH literally point at) are
# provided so either probe path hits.
{ lib
, stdenvNoCC
, fetchurl
}:

let
  commit = "22da2c3359151e0bbddaaa9804d4bf8de072051d";
  base = "https://raw.githubusercontent.com/TheMuppets/proprietary_vendor_samsung/${commit}/hero-common/proprietary/etc/wifi";

  bcmdhd = fetchurl {
    url = "${base}/bcmdhd_sta.bin_c0";
    hash = "sha256-iTmNowEzb1Ah+J/DtLiiMVOOqpyR3jy1G0RMlj1dAO0=";
  };
  nvram = fetchurl {
    url = "${base}/nvram_net.txt_c0";
    hash = "sha256-wsAGF7lgJb6RA+Q5bZxmWrknm5uPYnDSHh9gJDLwCmc=";
  };
in

stdenvNoCC.mkDerivation {
  pname = "firmware-samsung-hero";
  version = "1";

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    dir=$out/lib/firmware/postmarketos
    mkdir -p $dir
    install -Dm644 ${bcmdhd} $dir/bcmdhd_sta.bin_c0
    install -Dm644 ${nvram} $dir/nvram_net.txt_c0
    ln -s bcmdhd_sta.bin_c0 $dir/bcmdhd_sta.bin
    ln -s nvram_net.txt_c0 $dir/nvram_net.txt
    runHook postInstall
  '';

  meta = {
    description = "Non-free WiFi firmware for Samsung hero devices (BCM4359)";
    license = lib.licenses.unfree;
    platforms = [ "aarch64-linux" ];
  };
}
