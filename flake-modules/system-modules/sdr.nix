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

    # Local hardware SoapySDR plugins enabled on this host (excludes any device
    # claimed by ADS-B, and excludes soapyremote so SoapySDRServer only exports
    # local hardware without recursive network discovery).
    localSoapyPlugins =
      lib.optional cfg.devices.limesdr pkgs.limesuiteWithGui
      ++ lib.optional cfg.devices.airspy pkgs.soapyairspy
      ++ lib.optional cfg.devices.bladerf pkgs.soapybladerf
      ++ lib.optional cfg.devices.plutosdr pkgs.soapyplutosdr
      ++ lib.optional cfg.devices.rtlsdr pkgs.soapyrtlsdr
      ++ lib.optional cfg.devices.sdrplay pkgs.soapysdrplay
      ++ [
        pkgs.soapyaudio
        pkgs.soapyhackrf
        pkgs.soapyuhd
      ];

    # Full client plugin set (local hardware + SoapyRemote client support).
    enabledSoapyPlugins = localSoapyPlugins ++ [ pkgs.soapyremote ];

    soapyPluginSearchPath =
      lib.makeSearchPath pkgs.soapysdr.passthru.searchPath enabledSoapyPlugins;

    soapyServerPluginSearchPath =
      lib.makeSearchPath pkgs.soapysdr.passthru.searchPath localSoapyPlugins;

    soapysdrWithPlugins = pkgs.soapysdr.override {
      extraPackages = enabledSoapyPlugins;
    };

    defaultRemoteStr = lib.concatStringsSep "," cfg.soapyServer.remotes;

    soapySourceMainCpp = pkgs.writeText "soapy_source_main.cpp" ''
      #include <SoapySDR/Constants.h>
      #include <SoapySDR/Errors.hpp>
      #include <SoapySDR/Formats.hpp>
      #include <imgui.h>
      #include <utils/flog.h>
      #include <module.h>
      #include <gui/gui.h>
      #include <gui/widgets/stepped_slider.h>
      #include <signal_path/signal_path.h>
      #include <SoapySDR/Device.hpp>
      #include <SoapySDR/Modules.hpp>
      #include <SoapySDR/Logger.hpp>
      #include <core.h>
      #include <gui/style.h>
      #include <gui/smgui.h>
      #include <future>
      #include <sstream>
      #include <cstring>
      #include <algorithm>

      #define CONCAT(a, b) ((std::string(a) + b).c_str())

      SDRPP_MOD_INFO{
          /* Name:            */ "soapy_source",
          /* Description:     */ "SoapySDR source module for SDR++",
          /* Author:          */ "Ryzerth",
          /* Version:         */ 0, 2, 0,
          /* Max instances    */ 1
      };

      ConfigManager config;

      static const char* REMOTE_PROTS[] = { "udp", "tcp" };
      static const char* REMOTE_PROT_TXT = "UDP\0TCP\0";
      static const char* REMOTE_FMTS[] = { "auto", "CS16", "CS8", "CF32" };
      static const char* REMOTE_FMT_TXT = "Auto (Native)\0CS16 (16-bit)\0CS8 (8-bit)\0CF32 (32-bit float)\0";

      class SoapyModule : public ModuleManager::Instance {
      public:
          SoapyModule(std::string name) {
              this->name = name;

              uiGains = new float[1];
              std::memset(remoteHost, 0, sizeof(remoteHost));

              config.acquire();
              if (config.conf.contains("remote") && config.conf["remote"].is_string()) {
                  std::string rem = config.conf["remote"];
                  std::strncpy(remoteHost, rem.c_str(), sizeof(remoteHost) - 1);
              }
              std::string devName = config.conf.contains("device") && config.conf["device"].is_string()
                  ? std::string(config.conf["device"])
                  : "";
              config.release();

              refresh();
              selectDevice(devName);

              handler.ctx = this;
              handler.selectHandler = menuSelected;
              handler.deselectHandler = menuDeselected;
              handler.menuHandler = menuHandler;
              handler.startHandler = start;
              handler.stopHandler = stop;
              handler.tuneHandler = tune;
              handler.stream = &stream;
              sigpath::sourceManager.registerSource("SoapySDR", &handler);
          }

          ~SoapyModule() {
              stop(this);
              sigpath::sourceManager.unregisterSource("SoapySDR");
          }

          void postInit() {}

          void enable() {
              enabled = true;
          }

          void disable() {
              enabled = false;
          }

          bool isEnabled() {
              return enabled;
          }

          template <typename T>
          std::string to_string_with_precision(const T a_value, const int n = 6) {
              std::ostringstream out;
              out.precision(n);
              out << std::fixed << a_value;
              return out.str();
          }

      private:
          bool isRemoteDevice() const {
              return (devArgs.count("driver") && devArgs.at("driver") == "remote")
                  || devArgs.count("remote") > 0;
          }

          static std::vector<std::string> splitRemotes(const std::string& str) {
              std::vector<std::string> out;
              std::string cur;
              for (char c : str) {
                  if (c == ',' || c == ';' || c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                      if (!cur.empty()) {
                          out.push_back(cur);
                          cur.clear();
                      }
                  }
                  else {
                      cur += c;
                  }
              }
              if (!cur.empty()) {
                  out.push_back(cur);
              }
              return out;
          }

          void refresh() {
              txtDevList = "";
              devList.clear();

              auto localFuture = std::async(std::launch::async, []() -> SoapySDR::KwargsList {
                  try {
                      return SoapySDR::Device::enumerate();
                  }
                  catch (const std::exception& e) {
                      flog::error("Could not list local SoapySDR devices: {}", e.what());
                      return {};
                  }
              });

              auto remotes = splitRemotes(std::string(remoteHost));
              std::vector<std::pair<std::string, std::future<SoapySDR::KwargsList>>> remoteFutures;
              for (const auto& host : remotes) {
                  remoteFutures.emplace_back(host, std::async(std::launch::async, [host]() -> SoapySDR::KwargsList {
                      try {
                          SoapySDR::Kwargs args;
                          args["driver"] = "remote";
                          args["remote"] = host;
                          args["remote:timeout"] = "500000";
                          return SoapySDR::Device::enumerate(args);
                      }
                      catch (const std::exception& e) {
                          flog::warn("Could not query SoapySDRServer '{}': {}", host, e.what());
                          return {};
                      }
                  }));
              }

              devList = localFuture.get();

              for (auto& [host, fut] : remoteFutures) {
                  for (auto& rdev : fut.get()) {
                      std::string baseLabel;
                      if (rdev.count("label") && !rdev["label"].empty()) {
                          baseLabel = rdev["label"];
                      }
                      else if (rdev.count("remote:driver") && !rdev["remote:driver"].empty()) {
                          baseLabel = rdev["remote:driver"];
                          if (rdev.count("serial") && !rdev["serial"].empty()) {
                              baseLabel += " :: " + rdev["serial"];
                          }
                      }
                      else {
                          baseLabel = rdev.count("driver") && !rdev["driver"].empty() ? rdev["driver"] : "SoapySDR";
                      }

                      if (baseLabel.find(host) == std::string::npos) {
                          rdev["label"] = baseLabel + " [" + host + "]";
                      }
                      else {
                          rdev["label"] = baseLabel;
                      }
                      devList.push_back(rdev);
                  }
              }

              int i = 0;
              for (auto& dev : devList) {
                  if (!dev.count("label") || dev["label"].empty()) {
                      std::string lbl = dev.count("driver") && !dev["driver"].empty() ? dev["driver"] : "SoapySDR";
                      if (dev.count("serial") && !dev["serial"].empty()) {
                          lbl += " :: " + dev["serial"];
                      }
                      else {
                          lbl += " #" + std::to_string(i);
                      }
                      dev["label"] = lbl;
                  }
                  txtDevList += dev["label"];
                  txtDevList += '\0';
                  i++;
              }
          }

          float selectBwBySr(double samplerate) {
              float cur = bandwidthList[1];
              std::vector<float> bwListReversed = bandwidthList;
              std::reverse(bwListReversed.begin(), bwListReversed.end());
              for (auto bw : bwListReversed) {
                  if (bw >= samplerate) {
                      cur = bw;
                  }
                  else {
                      break;
                  }
              }
              flog::info("Bandwidth for samplerate {0} is {1}", samplerate, cur);
              return cur;
          }

          void selectSampleRate(double samplerate) {
              flog::info("Setting sample rate to {0}", samplerate);
              if (sampleRates.size() == 0) {
                  devId = -1;
                  return;
              }
              bool found = false;
              int i = 0;
              for (auto& sr : sampleRates) {
                  if (sr == samplerate) {
                      srId = i;
                      sampleRate = sr;
                      found = true;
                      core::setInputSampleRate(sampleRate);
                      break;
                  }
                  i++;
              }
              if (!found) {
                  selectSampleRate(sampleRates[0]);
              }
          }

          void selectDevice(std::string name) {
              if (devList.size() == 0) {
                  devId = -1;
                  return;
              }
              bool found = false;
              int i = 0;
              for (auto& args : devList) {
                  if (args["label"] == name) {
                      devArgs = args;
                      devId = i;
                      found = true;
                      break;
                  }
                  i++;
              }
              if (!found) {
                  devArgs = devList[0];
                  devId = 0;
                  name = devArgs["label"];
              }

              SoapySDR::Device* dev = NULL;
              try {
                  dev = SoapySDR::Device::make(devArgs);
              }
              catch (const std::exception& e) {
                  flog::error("Could not open device: {}", e.what());
                  return;
              }

              antennaList = dev->listAntennas(SOAPY_SDR_RX, channelId);
              txtAntennaList = "";
              for (const std::string& ant : antennaList) {
                  txtAntennaList += ant + '\0';
              }

              gainList = dev->listGains(SOAPY_SDR_RX, channelId);
              delete[] uiGains;
              uiGains = new float[std::max<size_t>(1, gainList.size())];
              gainRanges.clear();

              for (auto gain : gainList) {
                  gainRanges.push_back(dev->getGainRange(SOAPY_SDR_RX, channelId, gain));
              }

              SoapySDR::RangeList bandwidthRange = dev->getBandwidthRange(SOAPY_SDR_RX, channelId);

              txtBwList = "";
              bandwidthList.clear();
              bandwidthList.push_back(-1);
              txtBwList += "Auto";
              txtBwList += '\0';

              for (auto bwr : bandwidthRange) {
                  float bw = bwr.minimum();
                  bandwidthList.push_back(bw);
                  if (bw > 1.0e3 && bw <= 1.0e6) {
                      txtBwList += to_string_with_precision((bw / 1.0e3), 2) + " kHz";
                  }
                  else if (bw > 1.0e6) {
                      txtBwList += to_string_with_precision((bw / 1.0e6), 2) + " MHz";
                  }
                  else {
                      txtBwList += to_string_with_precision(bw, 0);
                  }
                  txtBwList += '\0';
              }

              sampleRates = dev->listSampleRates(SOAPY_SDR_RX, channelId);
              if (sampleRates.empty()) {
                  sampleRates.push_back(2.0e6);
              }
              txtSrList = "";
              for (double sr : sampleRates) {
                  if (sr > 1.0e3 && sr <= 1.0e6) {
                      txtSrList += to_string_with_precision((sr / 1.0e3), 2) + " kHz";
                  }
                  else if (sr > 1.0e6) {
                      txtSrList += to_string_with_precision((sr / 1.0e6), 2) + " MHz";
                  }
                  else {
                      txtSrList += to_string_with_precision(sr, 0);
                  }
                  txtSrList += '\0';
              }

              hasAgc = dev->hasGainMode(SOAPY_SDR_RX, channelId);

              SoapySDR::Device::unmake(dev);

              config.acquire();
              if (config.conf["devices"].contains(name)) {
                  if (config.conf["devices"][name].contains("antenna")) {
                      uiAntennaId = config.conf["devices"][name]["antenna"];
                  }
                  else {
                      uiAntennaId = 0;
                  }
                  int i = 0;
                  for (auto gain : gainList) {
                      if (config.conf["devices"][name]["gains"].contains(gain)) {
                          uiGains[i] = config.conf["devices"][name]["gains"][gain];
                      }
                      else {
                          uiGains[i] = gainRanges[i].minimum();
                      }
                      i++;
                  }
                  if (config.conf["devices"][name].contains("bandwidth")) {
                      uiBandwidthId = config.conf["devices"][name]["bandwidth"];
                  }
                  else if (bandwidthList.size() > 2) {
                      uiBandwidthId = 0;
                  }
                  if (hasAgc && config.conf["devices"][name].contains("agc")) {
                      agc = config.conf["devices"][name]["agc"];
                  }
                  else {
                      agc = false;
                  }
                  if (config.conf["devices"][name].contains("remoteProt")) {
                      remoteProtId = std::clamp<int>(config.conf["devices"][name]["remoteProt"], 0, 1);
                  }
                  else {
                      remoteProtId = 0;
                  }
                  if (config.conf["devices"][name].contains("remoteFmt")) {
                      remoteFmtId = std::clamp<int>(config.conf["devices"][name]["remoteFmt"], 0, 3);
                  }
                  else {
                      remoteFmtId = 1; // Default to CS16 for remote links
                  }
                  if (config.conf["devices"][name].contains("sampleRate")) {
                      selectSampleRate(config.conf["devices"][name]["sampleRate"]);
                  }
                  else {
                      selectSampleRate(sampleRates[0]);
                  }
              }
              else {
                  uiAntennaId = 0;
                  int i = 0;
                  for (auto gain : gainList) {
                      uiGains[i] = gainRanges[i].minimum();
                      i++;
                  }
                  if (bandwidthList.size() > 2)
                      uiBandwidthId = 0;
                  if (hasAgc) {
                      agc = false;
                  }
                  remoteProtId = 0;
                  remoteFmtId = 1; // CS16
                  selectSampleRate(sampleRates[0]);
              }
              config.release();
          }

          void saveCurrent() {
              json conf;
              conf["sampleRate"] = sampleRate;
              conf["antenna"] = uiAntennaId;
              int i = 0;
              for (auto gain : gainList) {
                  conf["gains"][gain] = uiGains[i];
                  i++;
              }
              if (bandwidthList.size() > 2)
                  conf["bandwidth"] = uiBandwidthId;
              if (hasAgc) {
                  conf["agc"] = agc;
              }
              conf["remoteProt"] = remoteProtId;
              conf["remoteFmt"] = remoteFmtId;
              config.acquire();
              config.conf["devices"][devArgs["label"]] = conf;
              config.release(true);
          }

          static void menuSelected(void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;
              flog::info("SoapyModule '{0}': Menu Select!", _this->name);
              if (_this->devList.size() == 0) {
                  return;
              }
              core::setInputSampleRate(_this->sampleRate);
          }

          static void menuDeselected(void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;
              flog::info("SoapyModule '{0}': Menu Deselect!", _this->name);
          }

          static void start(void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;
              if (_this->running) { return; }
              if (_this->devId < 0) {
                  flog::error("No device available");
                  return;
              }

              try {
                  _this->dev = SoapySDR::Device::make(_this->devArgs);
              }
              catch (const std::exception& e) {
                  flog::error("Failed to open device: {}", e.what());
                  return;
              }

              _this->dev->setSampleRate(SOAPY_SDR_RX, _this->channelId, _this->sampleRate);

              if (!_this->antennaList.empty() && _this->uiAntennaId >= 0 && _this->uiAntennaId < (int)_this->antennaList.size()) {
                  _this->dev->setAntenna(SOAPY_SDR_RX, _this->channelId, _this->antennaList[_this->uiAntennaId]);
              }

              if (_this->bandwidthList.size() > 2) {
                  if (_this->bandwidthList[_this->uiBandwidthId] == -1)
                      _this->dev->setBandwidth(SOAPY_SDR_RX, _this->channelId, _this->selectBwBySr(_this->sampleRates[_this->srId]));
                  else
                      _this->dev->setBandwidth(SOAPY_SDR_RX, _this->channelId, _this->bandwidthList[_this->uiBandwidthId]);
              }

              if (_this->hasAgc) {
                  _this->dev->setGainMode(SOAPY_SDR_RX, _this->channelId, _this->agc);
              }

              int i = 0;
              for (auto gain : _this->gainList) {
                  _this->dev->setGain(SOAPY_SDR_RX, _this->channelId, gain, _this->uiGains[i]);
                  i++;
              }

              _this->dev->setFrequency(SOAPY_SDR_RX, _this->channelId, _this->freq);

              SoapySDR::Kwargs streamArgs;
              if (_this->isRemoteDevice()) {
                  std::string prot = REMOTE_PROTS[std::clamp<int>(_this->remoteProtId, 0, 1)];
                  streamArgs["remote:prot"] = prot;
                  // Keep UDP datagrams under Netbird/WireGuard 1280 MTU to avoid IP fragmentation
                  if (prot == "udp") {
                      streamArgs["remote:mtu"] = "1200";
                  }
                  if (_this->remoteFmtId > 0) {
                      std::string reqFmt = REMOTE_FMTS[std::clamp<int>(_this->remoteFmtId, 0, 3)];
                      auto supported = _this->dev->getStreamFormats(SOAPY_SDR_RX, _this->channelId);
                      if (std::find(supported.begin(), supported.end(), reqFmt) != supported.end()) {
                          streamArgs["remote:format"] = reqFmt;
                      }
                  }
              }

              try {
                  _this->devStream = _this->dev->setupStream(SOAPY_SDR_RX, "CF32", std::vector<size_t>{ (size_t)_this->channelId }, streamArgs);
              }
              catch (const std::exception& e) {
                  flog::warn("setupStream with custom remote args failed ({}), falling back to default", e.what());
                  _this->devStream = _this->dev->setupStream(SOAPY_SDR_RX, "CF32");
              }

              _this->dev->activateStream(_this->devStream);
              _this->running = true;
              _this->workerThread = std::thread(_worker, _this);
              flog::info("SoapyModule '{0}': Start!", _this->name);
          }

          static void stop(void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;
              if (!_this->running) { return; }
              _this->running = false;
              _this->stream.stopWriter();
              _this->dev->deactivateStream(_this->devStream);
              if (_this->workerThread.joinable()) {
                  _this->workerThread.join();
              }
              _this->stream.clearWriteStop();
              _this->dev->closeStream(_this->devStream);
              SoapySDR::Device::unmake(_this->dev);

              flog::info("SoapyModule '{0}': Stop!", _this->name);
          }

          static void tune(double freq, void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;
              _this->freq = freq;
              if (_this->running) {
                  _this->dev->setFrequency(SOAPY_SDR_RX, _this->channelId, freq);
              }
              flog::info("SoapyModule '{0}': Tune: {1}!", _this->name, freq);
          }

          static void menuHandler(void* ctx) {
              SoapyModule* _this = (SoapyModule*)ctx;

              if (_this->running) { SmGui::BeginDisabled(); }

              SmGui::LeftLabel("Remote");
              SmGui::FillWidth();
              if (SmGui::InputText(CONCAT("##_soapy_remote_", _this->name), _this->remoteHost, sizeof(_this->remoteHost) - 1)) {
                  config.acquire();
                  config.conf["remote"] = std::string(_this->remoteHost);
                  config.release(true);
              }

              // If no device is selected, draw only the refresh button
              if (_this->devId < 0) {
                  SmGui::FillWidth();
                  SmGui::ForceSync();
                  if (SmGui::Button(CONCAT("Refresh##_dev_select_", _this->name))) {
                      _this->refresh();
                      config.acquire();
                      std::string defDev = config.conf.contains("device") && config.conf["device"].is_string()
                          ? std::string(config.conf["device"])
                          : "";
                      config.release();
                      _this->selectDevice(defDev);
                  }
                  if (_this->running) { SmGui::EndDisabled(); }
                  return;
              }

              SmGui::FillWidth();
              SmGui::ForceSync();
              if (SmGui::Combo(CONCAT("##_dev_select_", _this->name), &_this->devId, _this->txtDevList.c_str())) {
                  _this->selectDevice(_this->devList[_this->devId]["label"]);
                  config.acquire();
                  config.conf["device"] = _this->devList[_this->devId]["label"];
                  config.release(true);
              }

              if (SmGui::Combo(CONCAT("##_sr_select_", _this->name), &_this->srId, _this->txtSrList.c_str())) {
                  _this->selectSampleRate(_this->sampleRates[_this->srId]);
                  if (_this->bandwidthList.size() > 2 && _this->running && _this->bandwidthList[_this->uiBandwidthId] == -1)
                      _this->dev->setBandwidth(SOAPY_SDR_RX, _this->channelId, _this->selectBwBySr(_this->sampleRates[_this->srId]));
                  _this->saveCurrent();
              }

              SmGui::SameLine();
              SmGui::FillWidth();
              if (SmGui::Button(CONCAT("Refresh##_dev_select_", _this->name))) {
                  _this->refresh();
                  config.acquire();
                  std::string defDev = config.conf.contains("device") && config.conf["device"].is_string()
                      ? std::string(config.conf["device"])
                      : "";
                  config.release();
                  _this->selectDevice(defDev);
              }

              if (_this->isRemoteDevice()) {
                  SmGui::LeftLabel("Transport");
                  SmGui::FillWidth();
                  if (SmGui::Combo(CONCAT("##_remote_prot_", _this->name), &_this->remoteProtId, REMOTE_PROT_TXT)) {
                      _this->saveCurrent();
                  }

                  SmGui::LeftLabel("Wire Format");
                  SmGui::FillWidth();
                  if (SmGui::Combo(CONCAT("##_remote_fmt_", _this->name), &_this->remoteFmtId, REMOTE_FMT_TXT)) {
                      _this->saveCurrent();
                  }
              }

              if (_this->running) { SmGui::EndDisabled(); }

              if (_this->antennaList.size() > 1) {
                  SmGui::LeftLabel("Antenna");
                  SmGui::FillWidth();
                  if (SmGui::Combo(CONCAT("##_antenna_select_", _this->name), &_this->uiAntennaId, _this->txtAntennaList.c_str())) {
                      if (_this->running)
                          _this->dev->setAntenna(SOAPY_SDR_RX, _this->channelId, _this->antennaList[_this->uiAntennaId]);
                      _this->saveCurrent();
                  }
              }

              if (_this->hasAgc) {
                  if (SmGui::Checkbox((std::string("AGC##_agc_sel_") + _this->name).c_str(), &_this->agc)) {
                      if (_this->running) { _this->dev->setGainMode(SOAPY_SDR_RX, _this->channelId, _this->agc); }
                      if (!_this->agc) {
                          int i = 0;
                          for (auto gain : _this->gainList) {
                              _this->dev->setGain(SOAPY_SDR_RX, _this->channelId, gain, _this->uiGains[i]);
                              i++;
                          }
                      }
                      _this->saveCurrent();
                  }
              }

              int i = 0;
              char buf[128];
              for (auto gain : _this->gainList) {
                  sprintf(buf, "%s gain", gain.c_str());
                  SmGui::LeftLabel(buf);
                  float step = _this->gainRanges[i].step();
                  bool res;
                  SmGui::FillWidth();
                  if (step == 0.0f) {
                      res = SmGui::SliderFloat((std::string("##_gain_sel_") + _this->name + gain).c_str(), &_this->uiGains[i], _this->gainRanges[i].minimum(), _this->gainRanges[i].maximum());
                  }
                  else {
                      res = SmGui::SliderFloatWithSteps((std::string("##_gain_sel_") + _this->name + gain).c_str(), &_this->uiGains[i], _this->gainRanges[i].minimum(), _this->gainRanges[i].maximum(), step);
                  }
                  if (res) {
                      if (_this->running) {
                          _this->dev->setGain(SOAPY_SDR_RX, _this->channelId, gain, _this->uiGains[i]);
                      }
                      _this->saveCurrent();
                  }
                  i++;
              }
              if (_this->bandwidthList.size() > 2) {
                  SmGui::LeftLabel("Bandwidth");
                  SmGui::FillWidth();
                  if (SmGui::Combo(CONCAT("##_bw_select_", _this->name), &_this->uiBandwidthId, _this->txtBwList.c_str())) {
                      if (_this->running) {
                          if (_this->bandwidthList[_this->uiBandwidthId] == -1)
                              _this->dev->setBandwidth(SOAPY_SDR_RX, _this->channelId, _this->selectBwBySr(_this->sampleRates[_this->srId]));
                          else
                              _this->dev->setBandwidth(SOAPY_SDR_RX, _this->channelId, _this->bandwidthList[_this->uiBandwidthId]);
                      }
                      _this->saveCurrent();
                  }
              }
          }

          static void _worker(SoapyModule* _this) {
              int blockSize = std::clamp<int>((int)(_this->sampleRate / 200.0f), 1, STREAM_BUFFER_SIZE);
              int flags = 0;
              long long timeNs = 0;
              int offset = 0;

              while (_this->running) {
                  void* buffs[] = { _this->stream.writeBuf + offset };
                  int res = _this->dev->readStream(_this->devStream, buffs, blockSize - offset, flags, timeNs, 100000);
                  if (res <= 0) {
                      continue;
                  }
                  offset += res;
                  if (offset >= blockSize) {
                      if (!_this->stream.swap(offset)) { return; }
                      offset = 0;
                  }
              }
          }

          std::string name;
          bool enabled = true;
          dsp::stream<dsp::complex_t> stream;
          SoapySDR::Stream* devStream;
          SourceManager::SourceHandler handler;
          SoapySDR::KwargsList devList;
          SoapySDR::Kwargs devArgs;
          SoapySDR::Device* dev;
          std::string txtDevList;
          std::string txtSrList;
          std::thread workerThread;
          int devId = -1;
          double freq;
          double sampleRate;
          bool running = false;
          bool hasAgc = false;
          bool agc = false;
          std::vector<double> sampleRates;
          int srId = -1;
          float* uiGains;
          int channelCount = 1;
          int channelId = 0;
          int uiAntennaId = 0;
          std::vector<std::string> antennaList;
          std::string txtAntennaList;
          std::vector<std::string> gainList;
          std::vector<SoapySDR::Range> gainRanges;
          int uiBandwidthId = 0;
          std::vector<float> bandwidthList;
          std::string txtBwList;
          char remoteHost[1024];
          int remoteProtId = 0;
          int remoteFmtId = 1;
      };

      MOD_EXPORT void _INIT_() {
          config.setPath(core::args["root"].s() + "/soapy_source_config.json");
          json defConf;
          defConf["device"] = "";
          defConf["remote"] = "${defaultRemoteStr}";
          defConf["devices"] = json({});
          config.load(defConf);
          config.acquire();
          if (!config.conf.contains("remote") || !config.conf["remote"].is_string()) {
              config.conf["remote"] = "${defaultRemoteStr}";
          }
          config.release(true);
          config.enableAutoSave();
      }

      MOD_EXPORT ModuleManager::Instance* _CREATE_INSTANCE_(std::string name) {
          return new SoapyModule(name);
      }

      MOD_EXPORT void _DELETE_INSTANCE_(ModuleManager::Instance* instance) {
          delete (SoapyModule*)instance;
      }

      MOD_EXPORT void _END_() {
          config.disableAutoSave();
          config.save();
      }
    '';

    audioSinkMainCpp = pkgs.writeText "audio_sink_main.cpp" ''
      #include <imgui.h>
      #include <module.h>
      #include <gui/gui.h>
      #include <signal_path/signal_path.h>
      #include <signal_path/sink.h>
      #include <dsp/buffer/packer.h>
      #include <dsp/convert/stereo_to_mono.h>
      #include <utils/flog.h>
      #include <RtAudio.h>
      #include <config.h>
      #include <core.h>
      #include <cstring>

      #define CONCAT(a, b) ((std::string(a) + b).c_str())

      SDRPP_MOD_INFO{
          /* Name:            */ "audio_sink",
          /* Description:     */ "Audio sink module for SDR++",
          /* Author:          */ "Ryzerth",
          /* Version:         */ 0, 1, 0,
          /* Max instances    */ 1
      };

      ConfigManager config;

      class AudioSink : SinkManager::Sink {
      public:
          AudioSink(SinkManager::Stream* stream, std::string streamName) {
              _stream = stream;
              _streamName = streamName;
              s2m.init(_stream->sinkOut);
              monoPacker.init(&s2m.out, 512);
              stereoPacker.init(_stream->sinkOut, 512);

              playStateHandler.handler = onPlayStateChange;
              playStateHandler.ctx = this;
              gui::mainWindow.onPlayStateChange.bindHandler(&playStateHandler);

      #if RTAUDIO_VERSION_MAJOR >= 6
              audio.setErrorCallback(&errorCallback);
      #endif

              bool created = false;
              std::string device = "";
              config.acquire();
              if (!config.conf.contains(_streamName)) {
                  created = true;
                  config.conf[_streamName]["device"] = "";
                  config.conf[_streamName]["devices"] = json({});
              }
              device = config.conf[_streamName]["device"];
              config.release(created);

              RtAudio::DeviceInfo info;
      #if RTAUDIO_VERSION_MAJOR >= 6
              for (int i : audio.getDeviceIds()) {
      #else
              int count = audio.getDeviceCount();
              for (int i = 0; i < count; i++) {
      #endif
                  try {
                      info = audio.getDeviceInfo(i);
      #if !defined(RTAUDIO_VERSION_MAJOR) || RTAUDIO_VERSION_MAJOR < 6
                      if (!info.probed) { continue; }
      #endif
                      if (info.outputChannels == 0) { continue; }
                      if (info.isDefaultOutput) { defaultDevId = devList.size(); }
                      devList.push_back(info);
                      deviceIds.push_back(i);
                      txtDevList += info.name;
                      txtDevList += '\0';
                  }
                  catch (const std::exception& e) {
                      flog::error("AudioSinkModule Error getting audio device ({}) info: {}", i, e.what());
                  }
              }
              selectByName(device);
          }

          ~AudioSink() {
              gui::mainWindow.onPlayStateChange.unbindHandler(&playStateHandler);
              stop();
          }

          void start() {
              if (running) { return; }
              running = doStart();
          }

          void stop() {
              if (!running) { return; }
              doStop();
              running = false;
          }

          void selectFirst() {
              selectById(defaultDevId);
          }

          void selectByName(std::string name) {
              for (int i = 0; i < devList.size(); i++) {
                  if (devList[i].name == name) {
                      selectById(i);
                      return;
                  }
              }
              selectFirst();
          }

          void selectById(int id) {
              devId = id;
              bool created = false;
              config.acquire();
              if (!config.conf[_streamName]["devices"].contains(devList[id].name)) {
                  created = true;
                  config.conf[_streamName]["devices"][devList[id].name] = devList[id].preferredSampleRate;
              }
              sampleRate = config.conf[_streamName]["devices"][devList[id].name];
              config.release(created);

              sampleRates = devList[id].sampleRates;
              sampleRatesTxt = "";
              char buf[256];
              bool found = false;
              unsigned int defaultId = 0;
              unsigned int defaultSr = devList[id].preferredSampleRate;
              for (int i = 0; i < sampleRates.size(); i++) {
                  if (sampleRates[i] == sampleRate) {
                      found = true;
                      srId = i;
                  }
                  if (sampleRates[i] == defaultSr) {
                      defaultId = i;
                  }
                  sprintf(buf, "%d", sampleRates[i]);
                  sampleRatesTxt += buf;
                  sampleRatesTxt += '\0';
              }
              if (!found) {
                  sampleRate = defaultSr;
                  srId = defaultId;
              }

              _stream->setSampleRate(sampleRate);

              if (running) { doStop(); }
              if (running) { doStart(); }
          }

          void menuHandler() {
              float menuWidth = ImGui::GetContentRegionAvail().x;

              ImGui::SetNextItemWidth(menuWidth);
              if (ImGui::Combo(("##_audio_sink_dev_" + _streamName).c_str(), &devId, txtDevList.c_str())) {
                  selectById(devId);
                  config.acquire();
                  config.conf[_streamName]["device"] = devList[devId].name;
                  config.release(true);
              }

              ImGui::SetNextItemWidth(menuWidth);
              if (ImGui::Combo(("##_audio_sink_sr_" + _streamName).c_str(), &srId, sampleRatesTxt.c_str())) {
                  sampleRate = sampleRates[srId];
                  _stream->setSampleRate(sampleRate);
                  if (running) {
                      doStop();
                      doStart();
                  }
                  config.acquire();
                  config.conf[_streamName]["devices"][devList[devId].name] = sampleRate;
                  config.release(true);
              }
          }

      #if RTAUDIO_VERSION_MAJOR >= 6
          static void errorCallback(RtAudioErrorType type, const std::string& errorText) {
              switch (type) {
              case RtAudioErrorType::RTAUDIO_NO_ERROR:
                  return;
              case RtAudioErrorType::RTAUDIO_WARNING:
              case RtAudioErrorType::RTAUDIO_NO_DEVICES_FOUND:
              case RtAudioErrorType::RTAUDIO_DEVICE_DISCONNECT:
                  flog::warn("AudioSinkModule Warning: {} ({})", errorText, (int)type);
                  break;
              default:
                  throw std::runtime_error(errorText);
              }
          }
      #endif

      private:
          static void onPlayStateChange(bool newState, void* ctx) {
              AudioSink* _this = (AudioSink*)ctx;
              if (newState) {
                  _this->stereoPacker.out.clearReadStop();
              }
              else {
                  _this->stereoPacker.out.stopReader();
              }
          }

          bool doStart() {
              RtAudio::StreamParameters parameters;
              parameters.deviceId = deviceIds[devId];
              parameters.nChannels = 2;
              unsigned int bufferFrames = sampleRate / 60;
              RtAudio::StreamOptions opts;
              opts.streamName = _streamName;

              try {
                  if (gui::mainWindow.isPlaying()) {
                      stereoPacker.out.clearReadStop();
                  }
                  else {
                      stereoPacker.out.stopReader();
                  }
                  audio.openStream(&parameters, NULL, RTAUDIO_FLOAT32, sampleRate, &bufferFrames, &callback, this, &opts);
                  stereoPacker.setSampleCount(bufferFrames);
                  audio.startStream();
                  stereoPacker.start();
              }
              catch (const std::exception& e) {
                  flog::error("Could not open audio device {0}", e.what());
                  return false;
              }

              flog::info("RtAudio stream open");
              return true;
          }

          void doStop() {
              s2m.stop();
              monoPacker.stop();
              stereoPacker.stop();
              monoPacker.out.stopReader();
              stereoPacker.out.stopReader();
              audio.stopStream();
              audio.closeStream();
              monoPacker.out.clearReadStop();
              stereoPacker.out.clearReadStop();
          }

          static int callback(void* outputBuffer, void* inputBuffer, unsigned int nBufferFrames, double streamTime, RtAudioStreamStatus status, void* userData) {
              AudioSink* _this = (AudioSink*)userData;
              if (!gui::mainWindow.isPlaying()) {
                  std::memset(outputBuffer, 0, nBufferFrames * sizeof(dsp::stereo_t));
                  return 0;
              }
              int count = _this->stereoPacker.out.read();
              if (count < 0) {
                  std::memset(outputBuffer, 0, nBufferFrames * sizeof(dsp::stereo_t));
                  return 0;
              }

              std::memcpy(outputBuffer, _this->stereoPacker.out.readBuf, nBufferFrames * sizeof(dsp::stereo_t));
              _this->stereoPacker.out.flush();
              return 0;
          }

          SinkManager::Stream* _stream;
          dsp::convert::StereoToMono s2m;
          dsp::buffer::Packer<float> monoPacker;
          dsp::buffer::Packer<dsp::stereo_t> stereoPacker;
          EventHandler<bool> playStateHandler;

          std::string _streamName;

          int srId = 0;
          int devCount;
          int devId = 0;
          bool running = false;

          unsigned int defaultDevId = 0;

          std::vector<RtAudio::DeviceInfo> devList;
          std::vector<unsigned int> deviceIds;
          std::string txtDevList;

          std::vector<unsigned int> sampleRates;
          std::string sampleRatesTxt;
          unsigned int sampleRate = 48000;

          RtAudio audio;
      };

      class AudioSinkModule : public ModuleManager::Instance {
      public:
          AudioSinkModule(std::string name) {
              this->name = name;
              provider.create = create_sink;
              provider.ctx = this;

              sigpath::sinkManager.registerSinkProvider("Audio", provider);
          }

          ~AudioSinkModule() {
              // Unregister sink, this will automatically stop and delete all instances of the audio sink
              sigpath::sinkManager.unregisterSinkProvider("Audio");
          }

          void postInit() {}

          void enable() {
              enabled = true;
          }

          void disable() {
              enabled = false;
          }

          bool isEnabled() {
              return enabled;
          }

      private:
          static SinkManager::Sink* create_sink(SinkManager::Stream* stream, std::string streamName, void* ctx) {
              return (SinkManager::Sink*)(new AudioSink(stream, streamName));
          }

          std::string name;
          bool enabled = true;
          SinkManager::SinkProvider provider;
      };

      MOD_EXPORT void _INIT_() {
          json def = json({});
          config.setPath(core::args["root"].s() + "/audio_sink_config.json");
          config.load(def);
          config.enableAutoSave();
      }

      MOD_EXPORT void* _CREATE_INSTANCE_(std::string name) {
          AudioSinkModule* instance = new AudioSinkModule(name);
          return instance;
      }

      MOD_EXPORT void _DELETE_INSTANCE_(void* instance) {
          delete (AudioSinkModule*)instance;
      }

      MOD_EXPORT void _END_() {
          config.disableAutoSave();
          config.save();
      }
    '';

    sdrppCustom = (pkgs.sdrpp.override {
      airspy_source = cfg.devices.airspy;
      rtl_sdr_source = cfg.devices.rtlsdr;
      sdrplay_source = cfg.devices.sdrplay;
      soapysdr-with-plugins = soapysdrWithPlugins;
    }).overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
      postPatch = (old.postPatch or "") + ''
        cp ${soapySourceMainCpp} source_modules/soapy_source/src/main.cpp
        cp ${audioSinkMainCpp} sink_modules/audio_sink/src/main.cpp

        substituteInPlace core/src/core.cpp \
          --replace-fail \
            'defConfig["moduleInstances"]["SDR++ Server Source"]["enabled"] = true;' \
            'defConfig["moduleInstances"]["SDR++ Server Source"]["enabled"] = true;
        defConfig["moduleInstances"]["SoapySDR Source"]["module"] = "soapy_source";
        defConfig["moduleInstances"]["SoapySDR Source"]["enabled"] = true;' \
          --replace-fail \
            '// Update to new module representation in config if needed' \
            'if (!core::configManager.conf["moduleInstances"].contains("SoapySDR Source")) {
            core::configManager.conf["moduleInstances"]["SoapySDR Source"] = defConfig["moduleInstances"]["SoapySDR Source"];
        }
        // Update to new module representation in config if needed'
      '';
      postFixup = (old.postFixup or "") + ''
        wrapProgram "$out/bin/sdrpp" \
          --set-default SOAPY_SDR_PLUGIN_PATH "${soapyPluginSearchPath}"
      '';
    });
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
        remotes = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default =
            lib.filter (h: h != "${config.networking.hostName}.netbird.cloud") [
              "tungsten.netbird.cloud"
              "hispanas.netbird.cloud"
              "butthead.netbird.cloud"
              "lenovix.netbird.cloud"
            ];
          description = "Default remote SoapySDRServer hosts queried by SDR++ (editable in SDR++ UI for off-site hosts)";
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
      environment.variables.SOAPY_SDR_PLUGIN_PATH = soapyPluginSearchPath;
      environment.sessionVariables.SOAPY_SDR_PLUGIN_PATH = soapyPluginSearchPath;

      environment.systemPackages =
        lib.optionals cfg.devices.plutosdr [
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
          # SoapySDR CLI, remote server, and LimeSuite tools (SoapySDRUtil,
          # SoapySDRServer, LimeUtil, LimeQuickTest, LimeSuiteGUI) with all
          # enabled SoapySDR plugins baked in.
          soapysdrWithPlugins

          # General SDR receivers, DSP frameworks, and signal analyzers
          sdrppCustom             # SDR++ with SoapySDR remote host support & native sources
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
        environment.SOAPY_SDR_PLUGIN_PATH = soapyServerPluginSearchPath;
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
