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
      
      # GHC with Tidal packages for VS Code integration (includes base GHC)
      (haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ]))
      cabal-install
      
      # Audio utilities
      alsa-utils
      qjackctl
      pipewire
      pipewire.jack
      jack-example-tools
    ];

    # Headless startup script for systemd
    home.file.".local/share/SuperCollider/headless_startup.scd".text = ''
      // Load the main startup file
      load("~/.local/share/SuperCollider/startup.scd".standardizePath);
      
      "SuperDirt Systemd Daemon Started".postln;
      
      // Prevent sclang from exiting
      Condition.new.hang;
    '';

    # SuperCollider systemd service
    systemd.user.services.superdirt = {
      Unit = {
        Description = "SuperDirt (SuperCollider) Audio Engine";
        After = [ "pipewire.service" "jack.service" ];
      };
      Service = {
        ExecStartPre = "${pkgs.bash}/bin/bash -c '${pkgs.killall}/bin/killall scsynth || true'";
        ExecStart = let
          sc = "${pkgs.supercollider-with-sc3-plugins}/bin/sclang";
          pw = "${pkgs.pipewire.jack}/bin/pw-jack";
          headless = "${config.home.homeDirectory}/.local/share/SuperCollider/headless_startup.scd";
        in "${pw} ${sc} ${headless}";
        Restart = "on-failure";
        RestartSec = "15m";
      };
      Install = {
        WantedBy = [ "default.target" ];
      };
    };

    # Create TidalCycles boot file using standard BootTidal.hs
    home.file.".tidal/BootTidal.hs".text = ''
      :set -XOverloadedStrings
      :set prompt "tidal> "
      import Sound.Tidal.Context
      import qualified Sound.Tidal.Transition as T

      let editorTarget = Target {oName = "editor", oAddress = "127.0.0.1", oPort = 6013, oLatency = 0.03, oSchedule = Live, oWindow = Nothing, oHandshake = False, oBusPort = Nothing}
      let editorShape = OSCContext "/editor/highlights"
      tidal <- startStream (defaultConfig {cFrameTimespan = 1/20}) [(superdirtTarget {oAddress = "127.0.0.1", oPort = 57120, oLatency = 0.05}, [superdirtShape]), (editorTarget, [editorShape])]

      let p = streamReplace tidal
          hush = streamHush tidal
          list = streamList tidal
          mute = streamMute tidal
          unmute = streamUnmute tidal
          solo = streamSolo tidal
          unsolo = streamUnsolo tidal
          once = streamOnce tidal
          first = streamFirst tidal
          asap = once
          nudgeAll = streamNudgeAll tidal
          all = streamAll tidal
          resetCycles = streamResetCycles tidal
          setcps = asap . cps
          xfade i = transition tidal True (T.xfadeIn 4) i
          xfadeIn i t = transition tidal True (T.xfadeIn t) i
          histpan i = transition tidal True (T.histpan 4) i
          wait i t = transition tidal True (T.wait t) i
          wash i f t = transition tidal True (T.wash f id t) i
          washIn i f t = transition tidal True (T.washIn f t) i
          clutch i = transition tidal True (\_ h -> T.clutch 4 h) i
          clutchIn i t = transition tidal True (\_ h -> T.clutch t h) i
          anticipate i = transition tidal True (\_ h -> T.anticipate 4 h) i
          anticipateIn i t = transition tidal True (\_ h -> T.anticipate t h) i
          deltaContext _ _ p = p
          d1 = p 1 . (|< orbit 0)
          d2 = p 2 . (|< orbit 1)
          d3 = p 3 . (|< orbit 2)
          d4 = p 4 . (|< orbit 3)
          d5 = p 5 . (|< orbit 4)
          d6 = p 6 . (|< orbit 5)
          d7 = p 7 . (|< orbit 6)
          d8 = p 8 . (|< orbit 7)
          d9 = p 9 . (|< orbit 8)
          d10 = p 10 . (|< orbit 9)
          d11 = p 11 . (|< orbit 10)
          d12 = p 12 . (|< orbit 11)

      :set prompt "tidal> "
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
          s.options.numBuffers = 1024 * 256;
          s.options.memSize = 8192 * 64; // 512MB
          s.options.numWireBufs = 2048; // Fix for interconnect buffers
          s.options.numInputBusChannels = 0;
          s.options.numOutputBusChannels = 2;
          s.options.maxNodes = 1024 * 32;
          Server.default = s;

          // Boot server and start SuperDirt
          s.waitForBoot {
              ~dirt = SuperDirt(2, s);
              // Load default samples - this downloads and loads Dirt-Samples
              ~dirt.loadSoundFiles("/home/z-247/.local/share/SuperCollider/downloaded-quarks/Dirt-Samples/*");
              s.sync;
              ~dirt.start(57120, 0 ! 12);
              "SuperDirt started on port 57120".postln;
              "Available samples: ".postln;
              ~dirt.soundLibrary.postln;
          };
      });
    '';

    # Create GHC environment with Tidal packages
    home.file.".local/bin/tidal_ghci".text = ''
      #!/usr/bin/env bash
      # Start GHCi with Tidal packages available and BootTidal.hs as ghci script
      exec ${pkgs.haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ])}/bin/ghci -ghci-script ~/.tidal/BootTidal.hs "$@"
    '';
    
    home.file.".local/bin/tidal_ghci".executable = true;
    
    # Create ghc-pkg symlink for VS Code TidalCycles extension
    home.file.".local/bin/ghc-pkg".source = "${pkgs.haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ])}/bin/ghc-pkg";
    
    # Create ghc symlink for VS Code TidalCycles extension  
    home.file.".local/bin/ghc".source = "${pkgs.haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ])}/bin/ghc";
    
    # Create tidal directory structure that VS Code extension expects
    home.file.".local/bin/tidal/ghci".source = "${pkgs.haskellPackages.ghcWithPackages (p: [ p.tidal p.tidal-core p.tidal-link ])}/bin/ghci";
    

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
     
      # Start SuperCollider with SuperDirt
      echo "Starting SuperCollider with SuperDirt..."
      sclang ~/.local/share/SuperCollider/startup.scd &
      SC_PID=$!
      
      # Wait for SuperCollider to start and SuperDirt to load
      echo "Waiting for SuperDirt to start..."
      sleep 5
      
      # Start GHCi with TidalCycles
      echo "Starting TidalCycles..."
      ~/.local/bin/tidal_ghci
      
      # Clean up SuperCollider when GHCi exits
      kill $SC_PID 2>/dev/null
    '';
    
    home.file.".local/bin/tidal-start".executable = true;
  };
}
