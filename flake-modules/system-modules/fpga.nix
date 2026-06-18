{ inputs, ... }: {
  flake.modules.nixos.fpga =
# FPGA toolchains: the open-source flow plus FHS-wrapped proprietary vendor
# tools. Opt-in per host (add config.flake.modules.nixos.fpga to its modules).
#
# Vendor tools (Vivado, Quartus) come from nix-fpga as wrappers that read
# ~/.config/{vivado,quartus}/nix.sh (set INSTALL_DIR=/opt/...) at runtime. The
# toolchains are too large/licensed to fetch, so run the matching `vivado-shell`
# / `quartus-shell` once to install the vendor tarball you supply, then point
# nix.sh at it. See https://codeberg.org/Rutherther/nix-fpga
#
# Gowin EDA: the open-source path below (yosys + nextpnr + apycula +
# openFPGALoader) is the working route for Sipeed Tang Nano/Primer (Gowin
# GW1N/GW2A) and needs no license. The vendor Gowin EDA is also available via
# the nix-gowin-eda input, but it is upstream-WIP ("not working yet"), so it is
# intentionally NOT in the system closure. Try it on demand with:
#   nix run github:scottwillmoore/nix-gowin-eda#gowin-eda-education
{ config, lib, pkgs, ... }:
let
  fpga = inputs.nix-fpga.packages.${pkgs.stdenv.hostPlatform.system};
in {
  environment.systemPackages = [
    # Open-source flow — works out of the box, no license:
    #   yosys (synth) -> nextpnr (P&R; Gowin via himbaechel) -> apycula
    #   (Project Apicula bitstream) -> openFPGALoader (program).
    pkgs.yosys
    pkgs.nextpnr
    pkgs.python3Packages.apycula
    pkgs.openfpgaloader

    # Proprietary vendor toolchains (FHS-wrapped; installer supplied by you).
    fpga.vivado
    fpga.vivado-shell
    fpga.quartus
    fpga.quartus-shell
  ];

  # Device access for JTAG cables / FPGA programmers (Xilinx/Intel cables and
  # the Gowin/Tang programmers openFPGALoader supports). z-247 is already in
  # the dialout/plugdev groups.
  services.udev.packages = [
    fpga.vivado-udev-rules
    fpga.quartus-udev-rules
    pkgs.openfpgaloader
  ];
};
}
