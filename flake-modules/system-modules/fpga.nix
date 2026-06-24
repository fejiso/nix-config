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

  # --- Tang Dynasty (Anlogic TD) IDE — for the Lichee Tang (EG4S20) ----------
  # The proprietary Anlogic/Sipeed flow (synthesis + place-and-route + bitstream
  # for the EG4S20); there's no mature open-source route for Anlogic, so TD is
  # the tool the Lichee-Tang tutorial uses. Like Vivado/Quartus the installer is
  # licensed/large and user-supplied: download the TD Linux tarball from
  # dl.sipeed.com/TANG, unpack it, then point this wrapper at it by writing
  #   ~/.config/td/nix.sh:   export TD_HOME=/opt/Tang_Dynasty/td   # has bin/td
  # TD is an old Qt IDE, so this lib set is a FIRST CUT — if `td` reports a
  # missing .so, find it (ldd inside `td-shell`) and append it to tdTargetPkgs,
  # exactly how the Vivado FHS above was built up. If TD turns out to be 32-bit,
  # add the same libs under `multiPkgs` (buildFHSEnv) for the i686 set.
  tdTargetPkgs = p: with p; [
    stdenv.cc.cc.lib zlib glib glibc
    xorg.libX11 xorg.libXext xorg.libXrender xorg.libXi xorg.libXrandr
    xorg.libXfixes xorg.libXcursor xorg.libXScrnSaver xorg.libXtst
    xorg.libXcomposite xorg.libXdamage xorg.libXt xorg.libSM xorg.libICE
    xorg.libxcb xorg.libXau xorg.libXdmcp xorg.libXmu xorg.libXpm
    libGL libGLU freetype fontconfig libpng12 expat dbus.lib
    nss nspr cups.lib ncurses5 libusb1 e2fsprogs
  ];
  tdFhs = pkgs.buildFHSEnv {
    name = "td-fhs";
    targetPkgs = tdTargetPkgs;
    runScript = ''
      [ -f "$HOME/.config/td/nix.sh" ] && . "$HOME/.config/td/nix.sh"
      if [ -z "''${TD_HOME:-}" ]; then
        echo "td: set TD_HOME in ~/.config/td/nix.sh to your unpacked Tang" \
             "Dynasty dir (the one containing bin/td)" >&2
      else
        export PATH="$TD_HOME/bin:$PATH"
        export LD_LIBRARY_PATH="$TD_HOME/bin:$TD_HOME/lib:''${LD_LIBRARY_PATH:-}"
      fi
      # TD's GUI is Qt; mirror the Vivado workarounds for tiling WMs + software GL.
      export _JAVA_AWT_WM_NONREPARENTING=1
      export LIBGL_ALWAYS_SOFTWARE=1
      exec "$@"
    '';
    meta.mainProgram = "td-fhs";
  };
  # td-shell: FHS bash to install/inspect TD; td: launch the IDE.
  td-shell = pkgs.writeShellScriptBin "td-shell" ''exec ${lib.getExe tdFhs} bash "$@"'';
  td       = pkgs.writeShellScriptBin "td"       ''exec ${lib.getExe tdFhs} td "$@"'';
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
    # Vivado uses our pixman-patched FHS env (see above); Quartus is upstream;
    # Tang Dynasty (Anlogic, for the Lichee Tang) is the self-contained FHS above.
    vivado
    vivado-shell
    fpga.quartus
    fpga.quartus-shell
    td
    td-shell
  ];

  # Device access for JTAG cables / FPGA programmers (Xilinx/Intel cables and
  # the Gowin/Tang programmers openFPGALoader supports). z-247 is already in
  # the dialout/plugdev groups.
  services.udev.packages = [
    fpga.vivado-udev-rules
    fpga.quartus-udev-rules
    pkgs.openfpgaloader
  ];

  # Lichee Tang (Anlogic) onboard JTAG programmer. Its cable enumerates as a
  # Cypress/Anlogic device (VID 0547 / PID 1002); Tang Dynasty's downloader and
  # openFPGALoader need non-root access to it. This is Sipeed's own
  # 91-anlogic-jtag.rules (z-247 is already in plugdev). See
  # https://tang.sipeed.com/en/getting-started/installing-usb-driver/linux/
  services.udev.extraRules = ''
    SUBSYSTEMS=="usb", ATTRS{idVendor}=="0547", ATTRS{idProduct}=="1002", GROUP="plugdev", MODE="0660"
  '';
};
}
