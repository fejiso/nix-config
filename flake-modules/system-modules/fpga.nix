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
  system = pkgs.stdenv.hostPlatform.system;
  fpga = inputs.nix-fpga.packages.${system};

  # Vivado 2025.2 needs libs nix-fpga's FHS targetPkgs predate (e.g. pixman, for
  # libxv_tcltasks.so). We can't add them from OUR nixpkgs: this FHS uses an
  # older glibc, and mixing in glibc-2.42 libs triggers GLIBC_PRIVATE /
  # __nptl_change_stack_perm crashes. So rebuild the Vivado FHS env from
  # nix-fpga's OWN nixpkgs (which still has libstdcxx5 etc.), appending the
  # missing libs. Quartus/Gowin are left on the upstream packages.
  nfPkgs = import inputs.nix-fpga.inputs.nixpkgs { inherit system; };
  nfLib = import "${inputs.nix-fpga}/pkgs/common.nix" {
    pkgs = nfPkgs;
    inherit (nfPkgs) lib;
  };
  vivadoTargetPkgs = (import "${inputs.nix-fpga}/pkgs/xilinx/common.nix").targetPkgs;
  # Extra runtime libs newer Vivado/Vitis wants but the upstream list omits.
  # pixman + libpng (libpng16.so.16) are both needed by libxv_tcltasks.so.
  # libGL (libglvnd: libGL.so.1 / libGLX.so.0 / libGLdispatch.so.0) is the
  # vendor-neutral GL dispatch the GUI links against — without it inside the
  # FHS, the host's /run/opengl-driver libs aren't reachable and the canvas
  # renders blank.
  vivadoExtraLibs = p: [ p.pixman p.libpng p.libGL ];

  # Mirror nix-fpga's vivado/fhs.nix, only with the extra libs appended.
  mkVivadoFhs = requireInstallDir: nfPkgs.buildFHSEnv {
    name = "vivado";
    targetPkgs = p: (vivadoTargetPkgs p) ++ (vivadoExtraLibs p);
    runScript = ''
      ${nfLib.runScriptPrefix "vivado" requireInstallDir}
      if [[ ! -z $INSTALL_DIR ]]; then
        source $INSTALL_DIR/settings64.sh $INSTALL_DIR
      fi
      export LD_LIBRARY_PATH=/lib:$LD_LIBRARY_PATH
      # Vivado's GUI is Java/AWT; on non-reparenting WMs (niri, sway, i3) the
      # window paints blank without this. Harmless under reparenting WMs.
      export _JAVA_AWT_WM_NONREPARENTING=1
      # Force Mesa software GL (llvmpipe). The NVIDIA GLX path through
      # xwayland-satellite crashes Xwayland when Vivado opens a project (the X
      # connection drops -> _XIOError abort). llvmpipe is plenty for the 2D GUI.
      export LIBGL_ALWAYS_SOFTWARE=1
      # Expose the user's home-manager editor wrappers (wezterm, nvim/vim) so
      # they work as Vivado's custom editor, e.g. `wezterm start nvim`. These are
      # self-contained nix closures (own interpreter/libs), so they run fine in
      # the FHS. Also expose the system profile so the open-source EDA tools
      # above (verilator, gtkwave, sby, ...) are reachable from inside Vivado.
      # All appended, so Vivado's own bundled toolchain still takes priority.
      export PATH="$PATH:/run/current-system/sw/bin:/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin"
      exec "$@"
    '';
    meta.mainProgram = "vivado";
  };

  # vivado-shell: drops into an FHS bash (used to install + launch Vivado).
  vivado-shell = nfPkgs.writeShellScriptBin "vivado-shell" ''
    exec ${nfPkgs.lib.getExe (mkVivadoFhs false)} bash "$@"
  '';
  # vivado: the on-PATH wrappers (vivado, xsim, xsdb, …), generated against our
  # patched FHS env. (.override on fpga.vivado can't reach the inner fhsEnv, so
  # drive nix-fpga's generator directly with the same executables list.)
  vivado = nfLib.finalPkgGenerator.override {
    mainProgram = "vivado";
    fhsEnv = mkVivadoFhs true;
    executables = lib.unique [
      # Vivado bin/
      "bootgen" "cdoutil" "cdoutil_int" "combine_dfx_bitstreams" "cs_server"
      "diffbd" "hw_server" "hw_serverpv" "ldlibpath.sh" "loader"
      "manage_ipcache" "program_ftdi" "rdiArgs.sh" "setEnvAndRunCmd.sh"
      "setupEnv.sh" "stapl_player" "svf_utility" "symbol_server" "tcflog"
      "unsetldlibpath.sh" "unwrapped" "updatemem" "vivado" "vlm" "wbtcv" "xar"
      "xcd" "xcrg" "xelab" "xlicdiag" "xrcserver" "xrt_server" "xsc" "xsdb"
      "xsim" "xtclsh" "xvc_pcie" "xvhdl" "xvlog"
      # Vitis bin/
      "apcc" "hlsArgs.sh" "vitis_hls"
      # ModelComposer bin/
      "model_composer" "modelcomposerArgs.sh" "setPatchEnv.sh"
      # DocNav bin/
      "AppRun" "docnav" "lib" "libexec" "pdfjs" "plugins" "translations"
    ];
  };
in {
  environment.systemPackages = [
    # Open-source flow — works out of the box, no license:
    #   yosys (synth) -> nextpnr (P&R; Gowin via himbaechel) -> apycula
    #   (Project Apicula bitstream) -> openFPGALoader (program).
    pkgs.yosys
    pkgs.nextpnr
    pkgs.python3Packages.apycula
    pkgs.openfpgaloader

    # Simulation, waveform viewing, linting and formal verification. These are
    # native nix packages (no FHS needed); they're also put on the FHS PATH (via
    # /run/current-system/sw/bin in the vivado runScript) so Vivado can call them.
    pkgs.verilator                  # fast cycle-based Verilog/SystemVerilog sim
    pkgs.iverilog                   # Icarus: event-driven Verilog sim
    pkgs.ghdl                       # VHDL simulator (mcode)
    pkgs.nvc                        # modern VHDL simulator
    pkgs.gtkwave                    # waveform viewer (VCD/FST)
    pkgs.surfer                     # modern waveform viewer
    pkgs.verible                    # SystemVerilog linter/formatter/LS
    pkgs.python3Packages.cocotb     # Python cosimulation testbenches
    pkgs.sby                        # SymbiYosys: formal verification front-end
    pkgs.z3                         # SMT solver backend for formal flows

    # Proprietary vendor toolchains (FHS-wrapped; installer supplied by you).
    # Vivado uses our pixman-patched FHS env (see above); Quartus is upstream.
    vivado
    vivado-shell
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
