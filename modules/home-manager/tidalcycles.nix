{ config, pkgs, lib, ... }:

with lib;

{
  options.programs.tidalcycles = {
    enable = mkEnableOption "TidalCycles live coding environment";
  };

  config = mkIf config.programs.tidalcycles.enable {
    home.packages = with pkgs; [
      # Core TidalCycles packages
      haskellPackages.tidal
      haskellPackages.tidal-core
      haskellPackages.tidal-link
      
      # SuperCollider and audio engine
      supercollider-with-sc3-plugins
      
      # GHC and Haskell development tools
      ghc
      cabal-install
      
      # Audio utilities
      alsa-utils
      qjackctl
      pipewire
      pipewire.jack
      jack-example-tools
    ];

    # Create TidalCycles boot file
    home.file.".ghci".text = ''
      :set -XOverloadedStrings
      :set prompt "tidal> "
      import Sound.Tidal.Context
      tidal <- startTidal (superdirtTarget {oAddress = "127.0.0.1", oPort = 57120}) (defaultConfig {cFrameTimespan = 1/20})
      let d1 = streamReplace tidal 1
      let d2 = streamReplace tidal 2
      let d3 = streamReplace tidal 3
      let d4 = streamReplace tidal 4
      putStrLn "TidalCycles ready! Try: d1 $ s \"bd sn bd sn\""
    '';

    # SuperCollider startup script
    home.file.".local/share/SuperCollider/startup.scd".text = ''
      // Check if SuperDirt is installed, install if not
      if(Quarks.isInstalled("SuperDirt").not, {
          "SuperDirt not found. Installing...".postln;
          Quarks.checkForUpdates({
              Quarks.install("SuperDirt");
              "SuperDirt installed. Please restart SuperCollider and run tidal-start again.".postln;
          });
      }, {
          "SuperDirt found, starting...".postln;
          // Configure server options
          s.options.numBuffers = 1024 * 16; 
          s.options.memSize = 8192 * 16;
          s.options.numInputBusChannels = 0;
          s.options.numOutputBusChannels = 2;
          s.options.maxNodes = 1024 * 8;
          Server.default = s;

          // Boot server and start SuperDirt
          s.waitForBoot {
              ~dirt = SuperDirt(2, s);
              // Load default samples - this downloads and loads Dirt-Samples
              ~dirt.loadSoundFiles("/home/z-247/.local/share/SuperCollider/downloaded-quarks/Dirt-Samples/*");
              // Also try loading from default locations
              ~dirt.loadSoundFiles;
              s.sync;
              ~dirt.start(57120, 0 ! 12);
              "SuperDirt started on port 57120".postln;
              "Available samples: ".postln;
              ~dirt.soundLibrary.postln;
          };
      });
    '';

    # Create GHC environment with Tidal packages
    home.file.".local/bin/tidal-ghci".text = ''
      #!/usr/bin/env bash
      # Start GHCi with Tidal packages available
      ${pkgs.haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ])}/bin/ghci
    '';
    
    home.file.".local/bin/tidal-ghci".executable = true;

    # Create SuperDirt installation script
    home.file.".local/bin/tidal-install-superdirt".text = ''
      #!/usr/bin/env bash
      echo "Installing SuperDirt and Dirt-Samples via SuperCollider..."
      cat > /tmp/install_superdirt.scd << 'EOF'
"Updating Quarks...".postln;
Quarks.checkForUpdates({
    "Installing SuperDirt...".postln;
    Quarks.install("SuperDirt");
    "Installing Dirt-Samples...".postln;
    Quarks.install("Dirt-Samples");
    "Installation complete. You can now exit SuperCollider.".postln;
});
EOF
      echo "Starting SuperCollider to install SuperDirt and samples..."
      echo "Please wait for the installation to complete, then type 0.exit and press Enter to quit."
      sclang /tmp/install_superdirt.scd
      rm /tmp/install_superdirt.scd
    '';
    
    home.file.".local/bin/tidal-install-superdirt".executable = true;

    # Create helper scripts
    home.file.".local/bin/tidal-start".text = ''
      #!/usr/bin/env bash
      echo "Checking if SuperDirt is installed..."
      cat > /tmp/check_superdirt.scd << 'EOF'
if(Quarks.isInstalled("SuperDirt"), {"INSTALLED".postln}, {"NOT_INSTALLED".postln});
0.exit;
EOF
      if ! sclang /tmp/check_superdirt.scd 2>/dev/null | grep -q "INSTALLED"; then
          rm /tmp/check_superdirt.scd
          echo "SuperDirt not installed. Installing now..."
          ~/.local/bin/tidal-install-superdirt
          echo "SuperDirt installed. Please run tidal-start again."
          exit 0
      else
          rm /tmp/check_superdirt.scd
      fi
      
      # Start SuperCollider with SuperDirt using PipeWire JACK
      echo "Starting SuperCollider with SuperDirt..."
      pw-jack sclang ~/.local/share/SuperCollider/startup.scd &
      SC_PID=$!
      
      # Wait for SuperCollider to start and SuperDirt to load
      echo "Waiting for SuperDirt to start..."
      sleep 5
      
      # Start GHCi with TidalCycles
      echo "Starting TidalCycles..."
      ~/.local/bin/tidal-ghci
      
      # Clean up SuperCollider when GHCi exits
      kill $SC_PID 2>/dev/null
    '';
    
    home.file.".local/bin/tidal-start".executable = true;
  };
}