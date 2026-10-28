{ ... }: {
  flake.modules.nixos.sdr =
  # General SDR host configuration: drivers, udev rules, kernel module
  # blacklists, SoapySDR plugins, SoapySDRServer, and GUI/CLI SDR tools for:
  #   - Original LimeSDR (MyriadRF LMS7002M)
  #   - Analog Devices ADALM-PLUTO (PlutoSDR)
  #   - Nuand bladeRF
  #   - Airspy Mini
  #   - RTL-SDR
  #   - SDRplay RSP1 / RSP1A
  #
  # Automatically detects if an ADS-B module (`adsb-readsb`, `adsb-feeders`, or
  # `airspy-adsb`) is using `rtlsdr` or `airspy` on the host and excludes those
  # devices so `sdr` / `SoapySDRServer` never conflict with ADS-B decoding.
  { config, lib, pkgs, ... }:
  let
    cfg = config.sdr;

    # Detect whether an ADS-B module on this host is actively using RTL-SDR or Airspy.
    adsbUsesRtlsdr =
      ((config.services.adsb-readsb.enable or false) && (config.services.adsb-readsb.deviceType or "") == "rtlsdr")
      || ((config.services.adsb-feeders.adsbfi.enable or false) && (config.services.adsb-feeders.adsbfi.deviceType or "") == "rtlsdr");

    adsbUsesAirspy =
      (config.services.airspy-adsb.enable or false)
      || ((config.services.adsb-readsb.enable or false) && (config.services.adsb-readsb.deviceType or "") == "airspy")
      || ((config.services.adsb-feeders.adsbfi.enable or false) && (config.services.adsb-feeders.adsbfi.deviceType or "") == "airspy");

    # Whether `adsb-readsb` already manages RTL-SDR udev/kernel blacklists on this host.
    adsbManagesRtlsdrHw = config.services.adsb-readsb.enableRtlSdrHardware or false;

    sdrppWithSdrplay = pkgs.sdrpp.override {
      sdrplay_source = cfg.devices.sdrplay;
    };

    # SoapySDR plugins enabled on this host (excludes any device claimed by ADS-B).
    enabledSoapyPlugins =
      lib.optional cfg.devices.limesdr pkgs.limesuite
      ++ lib.optional cfg.devices.airspy pkgs.soapyairspy
      ++ lib.optional cfg.devices.bladerf pkgs.soapybladerf
      ++ lib.optional cfg.devices.plutosdr pkgs.soapyplutosdr
      ++ lib.optional cfg.devices.rtlsdr pkgs.soapyrtlsdr
      ++ lib.optional cfg.devices.sdrplay pkgs.soapysdrplay
      ++ [
        pkgs.soapyaudio
        pkgs.soapyhackrf
        pkgs.soapyremote
        pkgs.soapyuhd
      ];
  in
  {
    options.sdr = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable general SDR hardware support and software suite";
      };

      devices = {
        limesdr = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Original LimeSDR support";
        };
        plutosdr = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Analog Devices PlutoSDR support";
        };
        bladerf = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable Nuand bladeRF support";
        };
        airspy = lib.mkOption {
          type = lib.types.bool;
          default = !adsbUsesAirspy;
          defaultText = lib.literalExpression "!adsbUsesAirspy";
          description = "Enable Airspy Mini support (auto-disabled if used by ADS-B on this host)";
        };
        rtlsdr = lib.mkOption {
          type = lib.types.bool;
          default = !adsbUsesRtlsdr;
          defaultText = lib.literalExpression "!adsbUsesRtlsdr";
          description = "Enable RTL-SDR support (auto-disabled if used by ADS-B on this host)";
        };
        sdrplay = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SDRplay RSP1 / RSP1A support";
        };
      };

      soapyServer = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SoapySDRServer to share non-ADS-B SDR devices over wt0 (Netbird)";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 55132;
          description = "TCP port for SoapySDRServer";
        };
      };
    };

    config = lib.mkIf cfg.enable {
      # RTL-SDR: udev rules, rtl-sdr CLI tools, plugdev group, and DVB blacklists
      # (skip if ADS-B uses RTL-SDR or `adsb-readsb` already enables RTL-SDR hardware)
      hardware.rtl-sdr.enable = lib.mkIf (cfg.devices.rtlsdr && !adsbManagesRtlsdrHw) true;

      # Nuand bladeRF: udev rules (88-nuand-bladerf1.rules) and bladerf group
      hardware.bladeRF.enable = lib.mkIf cfg.devices.bladerf true;

      # SDRplay RSP1 / RSP1A: sdrplay_apiService daemon + 66-sdrplay.rules
      services.sdrplayApi.enable = lib.mkIf cfg.devices.sdrplay true;

      # Prevent kernel DVB/V4L2 drivers from claiming RTL-SDR (RTL2832U) or
      # SDRplay RSP1 (Mirics MSi001/MSi2500, 1df7:2500) USB interfaces.
      boot.blacklistedKernelModules =
        lib.optionals (cfg.devices.rtlsdr && !adsbManagesRtlsdrHw) [
          "dvb_usb_rtl28xxu"
          "dvb_usb_v2"
          "rtl2832"
          "rtl2830"
          "e4000"
        ]
        ++ lib.optionals cfg.devices.sdrplay [
          "msi001"
          "msi2500"
          "dvb_usb_msi2500"
        ];

      # Expose enabled SoapySDR modules (including soapysdrplay, and excluding any
      # device dedicated to ADS-B) to all local SoapySDR consumers.
      environment.variables.SOAPY_SDR_PLUGIN_PATH =
        lib.makeSearchPath pkgs.soapysdr.passthru.searchPath enabledSoapyPlugins;

      environment.systemPackages =
        lib.optionals cfg.devices.limesdr [
          pkgs.limesuiteWithGui   # LimeSDR: LimeUtil, LimeQuickTest, LimeSuiteGUI + MCU fw
        ]
        ++ lib.optionals cfg.devices.plutosdr [
          pkgs.libiio             # PlutoSDR: iio_info, iio_attr, iio_readdev, iio_writedev
          pkgs.libad9361          # PlutoSDR: AD9361/AD9363 baseband library
          pkgs.iio-oscilloscope   # PlutoSDR: Analog Devices IIO Oscilloscope GUI
        ]
        ++ lib.optionals cfg.devices.bladerf [
          pkgs.libbladeRF         # bladeRF: bladeRF-cli, bladeRF-fsk
        ]
        ++ lib.optionals cfg.devices.airspy [
          pkgs.airspy             # Airspy Mini: airspy_info, airspy_rx, airspy_spiflash
        ]
        ++ lib.optionals cfg.devices.rtlsdr [
          pkgs.rtl-sdr            # RTL-SDR: rtl_test, rtl_fm, rtl_tcp, rtl_power, rtl_sdr
          pkgs.rtl_433            # ISM band (433/868/915 MHz) protocol decoder
        ]
        ++ lib.optionals cfg.devices.sdrplay [
          pkgs.sdrplay            # SDRplay RSP1/RSP1A API & service
          pkgs.soapysdrplay
        ]
        ++ [
          # SoapySDR CLI & remote server (SoapySDRUtil, SoapySDRServer)
          pkgs.soapysdr
          pkgs.soapyremote

          # General SDR receivers, DSP frameworks, and signal analyzers
          sdrppWithSdrplay        # SDR++ with native Lime/Pluto/bladeRF/Airspy/RTL/SDRplay
          pkgs.gqrx               # Gqrx SDR receiver
          pkgs.cubicsdr           # CubicSDR receiver
          pkgs.sdrangel           # SDRangel Rx/Tx workstation + channel decoders
          pkgs.satdump            # SatDump satellite & general SDR receiver/decoder
          pkgs.sigdigger          # SigDigger real-time blind signal analyzer
          pkgs.quisk              # Quisk ham transceiver GUI
          pkgs.gnuradio           # GNU Radio + GNU Radio Companion
          pkgs.inspectrum         # Offline IQ spectrogram analyzer
          pkgs.urh                # Universal Radio Hacker

          # Digital-mode & ham audio UIs
          pkgs.fldigi             # Fldigi digital modem UI
          pkgs.wsjtx              # WSJT-X (FT8, JT65, WSPR, etc.)
          pkgs.js8call            # JS8Call weak-signal messaging
          pkgs.qsstv              # QSSTV slow-scan TV / DRM
        ];

      # Udev rules for enabled SDRs (RTL-SDR, bladeRF, and SDRplay udev packages
      # are added by their respective NixOS modules above).
      services.udev.packages =
        lib.optional cfg.devices.limesdr pkgs.limesuite
        ++ lib.optional cfg.devices.plutosdr pkgs.libiio
        ++ lib.optional cfg.devices.airspy pkgs.airspy;

      # Analog Devices ADALM-PLUTO (PlutoSDR) — normal (0456:b673) and DFU (0456:b674).
      # Direct USB node permissions (avoids libiio's shell/grep udev helper edge cases)
      # and ID_MM_DEVICE_IGNORE so ModemManager leaves Pluto's CDC ACM serial port alone.
      services.udev.extraRules = lib.mkIf cfg.devices.plutosdr ''
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0456", ATTRS{idProduct}=="b673", MODE="0660", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"
        SUBSYSTEM=="usb", ATTRS{idVendor}=="0456", ATTRS{idProduct}=="b674", MODE="0660", GROUP="plugdev", TAG+="uaccess", ENV{ID_MM_DEVICE_IGNORE}="1"
      '';

      users.groups.plugdev = { };
      users.groups.bladerf = { };
      users.users.z-247.extraGroups = [
        "plugdev"
        "bladerf"
      ];

      # SoapySDRServer: export non-ADS-B SDR devices over the network (firewalled to wt0)
      systemd.services.soapy-sdr-server = lib.mkIf cfg.soapyServer.enable {
        description = "SoapyRemote network server (non-ADS-B SDRs)";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        wantedBy = [ "multi-user.target" ];
        environment.SOAPY_SDR_PLUGIN_PATH =
          lib.makeSearchPath pkgs.soapysdr.passthru.searchPath enabledSoapyPlugins;
        serviceConfig = {
          ExecStart = "${pkgs.soapyremote}/bin/SoapySDRServer --bind=0.0.0.0:${toString cfg.soapyServer.port}";
          KillMode = "process";
          Restart = "on-failure";
          RestartSec = "5s";
          LimitRTPRIO = 99;
        };
      };

      # Increase socket buffer sizes for high-sample-rate IQ streaming (from soapyremote's sysctl.d)
      boot.kernel.sysctl = lib.mkIf cfg.soapyServer.enable {
        "net.core.rmem_max" = lib.mkDefault 104857600;
        "net.core.wmem_max" = lib.mkDefault 104857600;
      };

      # Restrict SoapySDRServer access strictly to the Netbird mesh interface (wt0):
      #   - TCP 55132: SoapyRemote RPC control & TCP transport
      #   - UDP 1900: SSDP service discovery
      #   - UDP 32768-60999: ephemeral UDP IQ stream sockets allocated per stream
      networking.firewall.interfaces.wt0 = lib.mkIf cfg.soapyServer.enable {
        allowedTCPPorts = [ cfg.soapyServer.port ];
        allowedUDPPorts = [ 1900 ];
        allowedUDPPortRanges = [
          { from = 32768; to = 60999; }
        ];
      };
    };
  };
}
