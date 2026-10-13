# BCM4339 WiFi firmware for the Nexus 5 (hammerhead). The blob itself is
# redistributable via linux-firmware; the board NVRAM calibration file is
# proprietary and vendored here from postmarketOS' firmware-lg-hammerhead
# package (which takes it from Google's m4b30z factory driver drop).
# Modem/ADSP/Bluetooth blobs from that package are intentionally left out —
# this port is a headless edge server.
{ linux-firmware
, runCommand
}:

runCommand "firmware-lg-hammerhead" { } ''
  d=$out/lib/firmware/brcm
  mkdir -p $d
  cp ${linux-firmware}/lib/firmware/brcm/brcmfmac4339-sdio.bin $d/
  install -Dm644 ${./brcmfmac4339-sdio.txt} $d/brcmfmac4339-sdio.txt
''
