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
      supercollider
      supercollider-with-sc3-plugins
      
      # Additional TidalCycles extensions
      haskellPackages.tidal-vis
      haskellPackages.tidal-serial
      
      # GHC and Haskell development tools
      ghc
      cabal-install
      
      # Audio tools and dependencies
      jack2
      qjackctl
      
      # Optional: Audio utilities
      pulseaudio
      alsa-utils
    ];

    # Create TidalCycles boot file
    home.file.".ghci".text = ''
      :set -XOverloadedStrings
      :set prompt ""
      :set prompt-cont ""
      import Sound.Tidal.Context
      tidal <- startTidal (superdirtTarget {oLatency = 0.1, oAddress = "127.0.0.1", oPort = 57120}) (defaultConfig {cCtrlListen = True, cFrameTimespan = 1/20})
      :set prompt "tidal> "
      :set prompt-cont ""
      let d1 = streamReplace tidal 1
      let d2 = streamReplace tidal 2
      let d3 = streamReplace tidal 3
      let d4 = streamReplace tidal 4
      let d5 = streamReplace tidal 5
      let d6 = streamReplace tidal 6
      let d7 = streamReplace tidal 7
      let d8 = streamReplace tidal 8
      let d9 = streamReplace tidal 9
      let d10 = streamReplace tidal 10
      let d11 = streamReplace tidal 11
      let d12 = streamReplace tidal 12
      let d13 = streamReplace tidal 13
      let d14 = streamReplace tidal 14
      let d15 = streamReplace tidal 15
      let d16 = streamReplace tidal 16
      let hush = streamHush tidal
      let list = streamList tidal
      let mute = streamMute tidal
      let unmute = streamUnmute tidal
      let solo = streamSolo tidal
      let unsolo = streamUnsolo tidal
      let once = streamOnce tidal
      let asap = streamAsap tidal
      let nudgeAll = streamNudgeAll tidal
      let all = streamAll tidal
      let resetCycles = streamResetCycles tidal
      let setcps = asap . cps
      let xfade i = transition tidal True (Sound.Tidal.Transition.xfadeIn 4) i
      let xfadeIn i t = transition tidal True (Sound.Tidal.Transition.xfadeIn t) i
      let histpan i t = transition tidal True (Sound.Tidal.Transition.histpan t) i
      let wait i t = transition tidal True (Sound.Tidal.Transition.wait t) i
      let waitT i f t = transition tidal True (Sound.Tidal.Transition.waitT f t) i
      let jump i = transition tidal True (Sound.Tidal.Transition.jump) i
      let jumpIn i t = transition tidal True (Sound.Tidal.Transition.jumpIn t) i
      let jumpIn' i t = transition tidal True (Sound.Tidal.Transition.jumpIn' t) i
      let jumpMod i t = transition tidal True (Sound.Tidal.Transition.jumpMod t) i
      let mortal i lifespan release = transition tidal True (Sound.Tidal.Transition.mortal lifespan release) i
      let interpolate i = transition tidal True (Sound.Tidal.Transition.interpolate) i
      let interpolateIn i t = transition tidal True (Sound.Tidal.Transition.interpolateIn t) i
      let clutch i = transition tidal True (Sound.Tidal.Transition.clutch) i
      let clutchIn i t = transition tidal True (Sound.Tidal.Transition.clutchIn t) i
      let anticipate i = transition tidal True (Sound.Tidal.Transition.anticipate) i
      let anticipateIn i t = transition tidal True (Sound.Tidal.Transition.anticipateIn t) i
      let forId i t = transition tidal False (Sound.Tidal.Transition.mortalOverlay t) i
      :set prompt "tidal> "
      :set prompt-cont ""
    '';

    # SuperCollider startup file for SuperDirt
    home.file.".local/share/SuperCollider/startup.scd".text = ''
      // Start SuperDirt automatically
      (
      s.options.numBuffers = 1024 * 256; // increase buffer number for loading samples
      s.options.memSize = 8192 * 32; // increase memory size
      s.options.numInputBusChannels = 2; // default number of input channels
      s.options.numOutputBusChannels = 2; // default number of output channels
      s.options.maxNodes = 1024 * 32; // increase max nodes

      s.waitForBoot {
          ~dirt = SuperDirt(2, s); // two output channels, increase if you want to pan across more channels
          ~dirt.loadSoundFiles; // load default samples
          s.sync; // wait for loading samples to finish
          ~dirt.start(57120, 0 ! 12); // start SuperDirt, listening on port 57120, create twelve orbits
      };
      )
    '';

    # Create helper scripts
    home.file.".local/bin/tidal-start".text = ''
      #!/usr/bin/env bash
      # Start SuperCollider with SuperDirt
      echo "Starting SuperCollider with SuperDirt..."
      sclang ~/.local/share/SuperCollider/startup.scd &
      
      # Wait a moment for SuperCollider to start
      sleep 3
      
      # Start GHCi with TidalCycles
      echo "Starting TidalCycles..."
      ghci
    '';
    
    home.file.".local/bin/tidal-start".executable = true;
  };
}