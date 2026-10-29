{ ... }: {
  flake.modules.nixos.sdr =
  # General SDR host configuration: drivers, udev rules, kernel module
  # blacklists, SoapySDR plugins, SoapySDRServer, SDR++ Server, and GUI/CLI SDR tools for:
  #   - Original LimeSDR (MyriadRF LMS7002M)
  #   - Analog Devices ADALM-PLUTO (PlutoSDR)
  #   - Nuand bladeRF
  #   - Airspy Mini
  #   - RTL-SDR
  #   - SDRplay RSP1 / RSP1A
  #
  # Automatically detects if an ADS-B module (`adsb-readsb`, `adsb-feeders`, or
  # `airspy-adsb`) is using `rtlsdr` or `airspy` on the host and excludes those
  # devices so `sdr` / `SoapySDRServer` / `sdrpp-server` never conflict with ADS-B decoding.
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
              config.release();

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

              auto remotes = core::args["server"].b()
                  ? std::vector<std::string>{}
                  : splitRemotes(std::string(remoteHost));
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
              if (!_this->running && (!_this->initialized || _this->devId < 0)) {
                  _this->refresh();
                  config.acquire();
                  std::string devName = config.conf.contains("device") && config.conf["device"].is_string()
                      ? std::string(config.conf["device"])
                      : "";
                  config.release();
                  _this->selectDevice(devName);
                  _this->initialized = true;
              }
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

              if (!core::args["server"].b()) {
                  SmGui::LeftLabel("Remote");
                  SmGui::FillWidth();
                  if (SmGui::InputText(CONCAT("##_soapy_remote_", _this->name), _this->remoteHost, sizeof(_this->remoteHost) - 1)) {
                      config.acquire();
                      config.conf["remote"] = std::string(_this->remoteHost);
                      config.release(true);
                  }
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
          double sampleRate = 2000000.0;
          bool running = false;
          bool initialized = false;
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

        substituteInPlace core/src/command_args.cpp \
          --replace-fail \
            'std::string root = (std::string)getenv("HOME") + "/.config/sdrpp";' \
            'const char* homeEnv = getenv("HOME");
        std::string root = std::string(homeEnv ? homeEnv : "/tmp") + "/.config/sdrpp";'

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
        // Update to new module representation in config if needed' \
          --replace-fail \
            '    // Shut down all modules
    for (auto& [name, mod] : core::moduleManager.modules) {
        mod.end();
    }' \
            '    // Stop any active source before shutting down modules
    sigpath::sourceManager.stop();

    // Shut down all modules
    for (auto& [name, mod] : core::moduleManager.modules) {
        mod.end();
    }'

        substituteInPlace core/src/utils/networking.cpp \
          --replace-fail \
            '        if (connectionOpen) {
#ifdef _WIN32
            closesocket(_sock);
#else
            ::shutdown(_sock, SHUT_RDWR);
            ::close(_sock);
#endif
        }

        // Wait for the theads to terminate
        if (readWorkerThread.joinable()) { readWorkerThread.join(); }
        if (writeWorkerThread.joinable()) { writeWorkerThread.join(); }' \
            '        if (_sock >= 0) {
#ifdef _WIN32
            closesocket(_sock);
#else
            ::shutdown(_sock, SHUT_RDWR);
            ::close(_sock);
#endif
            _sock = -1;
        }

        // Wait for the threads to terminate (avoid self-join if called from worker)
        if (readWorkerThread.joinable()) {
            if (std::this_thread::get_id() == readWorkerThread.get_id()) { readWorkerThread.detach(); }
            else { readWorkerThread.join(); }
        }
        if (writeWorkerThread.joinable()) {
            if (std::this_thread::get_id() == writeWorkerThread.get_id()) { writeWorkerThread.detach(); }
            else { writeWorkerThread.join(); }
        }' \
          --replace-fail \
            '        int beenWritten = 0;
        while (beenWritten < count) {
            ret = send(_sock, (char*)buf, count, 0);
            if (ret <= 0) {' \
            '        int beenWritten = 0;
        while (beenWritten < count) {
#ifdef MSG_NOSIGNAL
            ret = send(_sock, (char*)&buf[beenWritten], count - beenWritten, MSG_NOSIGNAL);
#else
            ret = send(_sock, (char*)&buf[beenWritten], count - beenWritten, 0);
#endif
            if (ret <= 0) {'

        substituteInPlace core/src/server.cpp \
          --replace-fail \
            'if (fn.find("source") == std::string::npos) { continue; }' \
            'if (fn.find("source") == std::string::npos || fn == "audio_source.so") { continue; }' \
          --replace-fail \
            '        // Load sourceId from config
        sourceId = 0;
        if (sourceList.keyExists(sourceName)) { sourceId = sourceList.keyId(sourceName); }
        sigpath::sourceManager.selectSource(sourceList[sourceId]);

        // TODO: Use command line option
        std::string host = (std::string)core::args["addr"];
        int port = (int)core::args["port"];
        listener = net::listen(host, port);
        listener->acceptAsync(_clientHandler, NULL);

        flog::info("Ready, listening on {0}:{1}", host, port);
        while(1) { std::this_thread::sleep_for(std::chrono::milliseconds(100)); }

        return 0;
    }

    void _clientHandler(net::Conn conn, void* ctx) {
        // Reject if someone else is already connected
        if (client && client->isOpen()) {
            flog::info("REJECTED Connection from {0}:{1}, another client is already connected.", "TODO", "TODO");
            
            // Issue a disconnect command to the client
            uint8_t buf[sizeof(PacketHeader) + sizeof(CommandHeader)];
            PacketHeader* tmp_phdr = (PacketHeader*)buf;
            CommandHeader* tmp_chdr = (CommandHeader*)&buf[sizeof(PacketHeader)];
            tmp_phdr->size = sizeof(PacketHeader) + sizeof(CommandHeader);
            tmp_phdr->type = PACKET_TYPE_COMMAND;
            tmp_chdr->cmd = COMMAND_DISCONNECT;
            conn->write(tmp_phdr->size, buf);

            // TODO: Find something cleaner
            std::this_thread::sleep_for(std::chrono::milliseconds(100));

            conn->close();
            
            // Start another async accept
            listener->acceptAsync(_clientHandler, NULL);
            return;
        }

        flog::info("Connection from {0}:{1}", "TODO", "TODO");
        client = std::move(conn);
        client->readAsync(sizeof(PacketHeader), rbuf, _packetHandler, NULL);

        // Perform settings reset
        sigpath::sourceManager.stop();
        comp.setPCMType(dsp::compression::PCM_TYPE_I16);
        compression = false;

        sendSampleRate(sampleRate);

        // TODO: Wait otherwise someone else could connect

        listener->acceptAsync(_clientHandler, NULL);
    }

    void _packetHandler(int count, uint8_t* buf, void* ctx) {
        PacketHeader* hdr = (PacketHeader*)buf;

        // Read the rest of the data (TODO: CHECK SIZE OR SHIT WILL BE FUCKED + ADD TIMEOUT)
        int len = 0;
        int read = 0;
        int goal = hdr->size - sizeof(PacketHeader);
        while (len < goal) {
            read = client->read(goal - len, &buf[sizeof(PacketHeader) + len]);
            if (read < 0) { return; };
            len += read;
        }' \
            '        // Load sourceId from config (defer selectSource until a client connects
        // so sdrpp --server does not open or lock any SDR device while idle)
        sourceId = 0;
        if (sourceList.keyExists(sourceName)) { sourceId = sourceList.keyId(sourceName); }

        // TODO: Use command line option
        std::string host = (std::string)core::args["addr"];
        int port = (int)core::args["port"];
        listener = net::listen(host, port);
        listener->acceptAsync(_clientHandler, NULL);

        flog::info("Ready, listening on {0}:{1}", host, port);
        while(1) {
            std::this_thread::sleep_for(std::chrono::milliseconds(100));
            if (running && (!client || !client->isOpen())) {
                flog::info("Client disconnected, stopping active source");
                sigpath::sourceManager.stop();
                running = false;
            }
        }

        return 0;
    }

    void _clientHandler(net::Conn conn, void* ctx) {
        // Reject if someone else is already connected
        if (client && client->isOpen()) {
            flog::info("REJECTED Connection from {0}:{1}, another client is already connected.", "TODO", "TODO");
            
            // Issue a disconnect command to the client
            uint8_t buf[sizeof(PacketHeader) + sizeof(CommandHeader)];
            PacketHeader* tmp_phdr = (PacketHeader*)buf;
            CommandHeader* tmp_chdr = (CommandHeader*)&buf[sizeof(PacketHeader)];
            tmp_phdr->size = sizeof(PacketHeader) + sizeof(CommandHeader);
            tmp_phdr->type = PACKET_TYPE_COMMAND;
            tmp_chdr->cmd = COMMAND_DISCONNECT;
            conn->write(tmp_phdr->size, buf);

            // TODO: Find something cleaner
            std::this_thread::sleep_for(std::chrono::milliseconds(100));

            conn->close();
            
            // Start another async accept
            listener->acceptAsync(_clientHandler, NULL);
            return;
        }

        flog::info("Connection from {0}:{1}", "TODO", "TODO");

        // Perform settings reset and select source now that a client is connected
        sigpath::sourceManager.stop();
        running = false;
        if (!sourceList.empty()) {
            sigpath::sourceManager.selectSource(sourceList[sourceId]);
        }
        comp.setPCMType(dsp::compression::PCM_TYPE_I16);
        compression = false;

        client = std::move(conn);
        sendSampleRate(sampleRate);
        client->readAsync(sizeof(PacketHeader), rbuf, _packetHandler, NULL);

        // TODO: Wait otherwise someone else could connect

        listener->acceptAsync(_clientHandler, NULL);
    }

    void _packetHandler(int count, uint8_t* buf, void* ctx) {
        PacketHeader* hdr = (PacketHeader*)buf;

        // Read the rest of the data (TODO: CHECK SIZE OR SHIT WILL BE FUCKED + ADD TIMEOUT)
        int len = 0;
        int read = 0;
        int goal = hdr->size - sizeof(PacketHeader);
        while (len < goal) {
            read = client->read(goal - len, &buf[sizeof(PacketHeader) + len]);
            if (read <= 0) {
                if (running) {
                    sigpath::sourceManager.stop();
                    running = false;
                }
                return;
            }
            len += read;
        }'

        # SDR++ Server Source (client): disconnect cleanly on deselect/exit and add fleet host presets
        substituteInPlace source_modules/sdrpp_server_source/src/main.cpp \
          --replace-fail \
            '    ~SDRPPServerSourceModule() {
        stop(this);
        sigpath::sourceManager.unregisterSource("SDR++ Server");
    }' \
            '    ~SDRPPServerSourceModule() {
        stop(this);
        if (connected()) { client->close(); }
        sigpath::sourceManager.unregisterSource("SDR++ Server");
    }' \
          --replace-fail \
            '    static void menuDeselected(void* ctx) {
        SDRPPServerSourceModule* _this = (SDRPPServerSourceModule*)ctx;
        gui::mainWindow.playButtonLocked = false;
        flog::info("SDRPPServerSourceModule '\'''{0}'\''': Menu Deselect!", _this->name);
    }' \
            '    static void menuDeselected(void* ctx) {
        SDRPPServerSourceModule* _this = (SDRPPServerSourceModule*)ctx;
        if (_this->running) { stop(_this); }
        if (_this->connected()) { _this->client->close(); }
        gui::mainWindow.playButtonLocked = false;
        flog::info("SDRPPServerSourceModule '\'''{0}'\''': Menu Deselect!", _this->name);
    }' \
          --replace-fail \
            '        if (connected) { style::beginDisabled(); }
        if (ImGui::InputText(CONCAT("##sdrpp_srv_srv_host_", _this->name), _this->hostname, 1023)) {' \
            '        if (connected) { style::beginDisabled(); }
        {
            static const char* presetHosts[] = { "Custom", "localhost"${lib.concatMapStrings (h: '', "${h}"'') cfg.soapyServer.remotes} };
            static const int presetCount = sizeof(presetHosts) / sizeof(presetHosts[0]);
            int curPreset = 0;
            for (int i = 1; i < presetCount; i++) {
                if (std::string(_this->hostname) == presetHosts[i]) { curPreset = i; break; }
            }
            ImGui::LeftLabel("Host");
            ImGui::FillWidth();
            if (ImGui::Combo(CONCAT("##sdrpp_srv_preset_", _this->name), &curPreset, "Custom\0localhost\0${lib.concatMapStrings (h: "${h}\\0") cfg.soapyServer.remotes}")) {
                if (curPreset > 0) {
                    std::strncpy(_this->hostname, presetHosts[curPreset], 1023);
                    _this->hostname[1023] = 0;
                    config.acquire();
                    config.conf["hostname"] = _this->hostname;
                    config.release(true);
                }
            }
        }
        if (ImGui::InputText(CONCAT("##sdrpp_srv_srv_host_", _this->name), _this->hostname, 1023)) {' \
          --replace-fail \
            '    def["hostname"] = "localhost";
    def["port"] = 5259;' \
            '    def["hostname"] = "${if cfg.soapyServer.remotes != [ ] then lib.head cfg.soapyServer.remotes else "localhost"}";
    def["port"] = ${toString cfg.sdrppServer.port};'

        # SDRplay source: never hold sdrplay_api_Open or sdrplay_api_SelectDevice while idle;
        # only open API during refresh() and between start() and stop().
        substituteInPlace source_modules/sdrplay_source/src/main.cpp \
          --replace-fail \
            '        sdrplay_api_ErrT err = sdrplay_api_Open();
        if (err != sdrplay_api_Success) {
            flog::error("Could not intiatialized the SDRplay API. Make sure that the service is running.");
            return;
        }

        sampleRate = 2000000.0;
        srId = 0;

        bandwidth = sdrplay_api_BW_5_000;
        bandwidthId = 8;

        handler.ctx = this;
        handler.selectHandler = menuSelected;
        handler.deselectHandler = menuDeselected;
        handler.menuHandler = menuHandler;
        handler.startHandler = start;
        handler.stopHandler = stop;
        handler.tuneHandler = tune;
        handler.stream = &stream;

        refresh();

        config.acquire();
        std::string confSelectDev = config.conf["device"];
        config.release();
        selectByName(confSelectDev);

        sigpath::sourceManager.registerSource("SDRplay", &handler);

        initOk = true;' \
            '        sampleRate = 2000000.0;
        srId = 0;

        bandwidth = sdrplay_api_BW_5_000;
        bandwidthId = 8;

        samplerates.clear();
        samplerates.define(2e6, "2MHz", 2e6);
        samplerates.define(3e6, "3MHz", 3e6);
        samplerates.define(4e6, "4MHz", 4e6);
        samplerates.define(5e6, "5MHz", 5e6);
        samplerates.define(6e6, "6MHz", 6e6);
        samplerates.define(7e6, "7MHz", 7e6);
        samplerates.define(8e6, "8MHz", 8e6);
        samplerates.define(9e6, "9MHz", 9e6);
        samplerates.define(10e6, "10MHz", 10e6);

        bandwidths.clear();
        bandwidths.define(200e3, "200KHz", sdrplay_api_BW_0_200);
        bandwidths.define(300e3, "300KHz", sdrplay_api_BW_0_300);
        bandwidths.define(600e3, "600KHz", sdrplay_api_BW_0_600);
        bandwidths.define(1.536e6, "1.536MHz", sdrplay_api_BW_1_536);
        bandwidths.define(5e6, "5MHz", sdrplay_api_BW_5_000);
        bandwidths.define(6e6, "6MHz", sdrplay_api_BW_6_000);
        bandwidths.define(7e6, "7MHz", sdrplay_api_BW_7_000);
        bandwidths.define(8e6, "8MHz", sdrplay_api_BW_8_000);
        bandwidths.define(0, "Auto", sdrplay_api_BW_Undefined);

        handler.ctx = this;
        handler.selectHandler = menuSelected;
        handler.deselectHandler = menuDeselected;
        handler.menuHandler = menuHandler;
        handler.startHandler = start;
        handler.stopHandler = stop;
        handler.tuneHandler = tune;
        handler.stream = &stream;

        sigpath::sourceManager.registerSource("SDRplay", &handler);' \
          --replace-fail \
            '        sdrplay_api_DeviceT devArr[MAX_DEV_COUNT];
        unsigned int numDev = 0;
        sdrplay_api_GetDevices(devArr, &numDev, MAX_DEV_COUNT);' \
            '        bool openedHere = false;
        if (!initOk) {
            if (sdrplay_api_Open() != sdrplay_api_Success) {
                flog::error("Could not initialize the SDRplay API. Make sure that the service is running.");
                return;
            }
            initOk = true;
            openedHere = true;
        }
        sdrplay_api_DeviceT devArr[MAX_DEV_COUNT];
        unsigned int numDev = 0;
        sdrplay_api_LockDeviceApi();
        sdrplay_api_GetDevices(devArr, &numDev, MAX_DEV_COUNT);
        sdrplay_api_UnlockDeviceApi();
        if (openedHere && !running) {
            sdrplay_api_Close();
            initOk = false;
        }' \
          --replace-fail \
            '    void selectDev(sdrplay_api_DeviceT dev, int id) {
        openDev = dev;
        sdrplay_api_ErrT err;

        openDev.tuner = sdrplay_api_Tuner_A;
        openDev.rspDuoMode = sdrplay_api_RspDuoMode_Single_Tuner;
        err = sdrplay_api_SelectDevice(&openDev);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not select RSP device: {0}", errStr);
            selectedName = "";
            return;
        }

        sdrplay_api_UnlockDeviceApi();
        sdrplay_api_DebugEnable(openDev.dev, sdrplay_api_DbgLvl_Message);

        err = sdrplay_api_GetDeviceParams(openDev.dev, &openDevParams);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not get device params for RSP device: {0}", errStr);
            selectedName = "";
            return;
        }

        err = sdrplay_api_Init(openDev.dev, &cbFuncs, this);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not init RSP device: {0}", errStr);
            selectedName = "";
            return;
        }

        // Define the valid samplerates
        samplerates.clear();
        samplerates.define(2e6, "2MHz", 2e6);
        samplerates.define(3e6, "3MHz", 3e6);
        samplerates.define(4e6, "4MHz", 4e6);
        samplerates.define(5e6, "5MHz", 5e6);
        samplerates.define(6e6, "6MHz", 6e6);
        samplerates.define(7e6, "7MHz", 7e6);
        samplerates.define(8e6, "8MHz", 8e6);
        samplerates.define(9e6, "9MHz", 9e6);
        samplerates.define(10e6, "10MHz", 10e6);

        // Define the valid bandwidths
        bandwidths.clear();
        bandwidths.define(200e3, "200KHz", sdrplay_api_BW_0_200);
        bandwidths.define(300e3, "300KHz", sdrplay_api_BW_0_300);
        bandwidths.define(600e3, "600KHz", sdrplay_api_BW_0_600);
        bandwidths.define(1.536e6, "1.536MHz", sdrplay_api_BW_1_536);
        bandwidths.define(5e6, "5MHz", sdrplay_api_BW_5_000);
        bandwidths.define(6e6, "6MHz", sdrplay_api_BW_6_000);
        bandwidths.define(7e6, "7MHz", sdrplay_api_BW_7_000);
        bandwidths.define(8e6, "8MHz", sdrplay_api_BW_8_000);
        bandwidths.define(0, "Auto", sdrplay_api_BW_Undefined);

        channelParams = openDevParams->rxChannelA;

        selectedName = devNameList[id];' \
            '    void selectDev(sdrplay_api_DeviceT dev, int id) {
        openDev = dev;
        devId = id;
        selectedName = devNameList[id];' \
          --replace-fail \
            '        // Release device after selecting
        sdrplay_api_Uninit(openDev.dev);
        sdrplay_api_ReleaseDevice(&openDev);
    }' \
            '    }' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        SDRPlaySourceModule* _this = (SDRPlaySourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("SDRPlaySourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        SDRPlaySourceModule* _this = (SDRPlaySourceModule*)ctx;
        if (!_this->running && _this->selectedName.empty()) {
            _this->refresh();
            config.acquire();
            std::string confSelectDev = config.conf["device"];
            config.release();
            _this->selectByName(confSelectDev);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("SDRPlaySourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
          --replace-fail \
            '        // First, acquire device
        sdrplay_api_ErrT err;

        _this->openDev.tuner = sdrplay_api_Tuner_A;
        _this->openDev.rspDuoMode = sdrplay_api_RspDuoMode_Single_Tuner;
        err = sdrplay_api_SelectDevice(&_this->openDev);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not select RSP device: {0}", errStr);
            _this->selectedName = "";
            return;
        }

        sdrplay_api_UnlockDeviceApi();
        sdrplay_api_DebugEnable(_this->openDev.dev, sdrplay_api_DbgLvl_Message);

        err = sdrplay_api_GetDeviceParams(_this->openDev.dev, &_this->openDevParams);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not get device params for RSP device: {0}", errStr);
            _this->selectedName = "";
            return;
        }

        err = sdrplay_api_Init(_this->openDev.dev, &_this->cbFuncs, _this);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not init RSP device: {0}", errStr);
            _this->selectedName = "";
            return;
        }' \
            '        if (_this->selectedName.empty()) { return; }

        // First, open API and acquire device
        sdrplay_api_ErrT err;
        if (!_this->initOk) {
            err = sdrplay_api_Open();
            if (err != sdrplay_api_Success) {
                flog::error("Could not open SDRplay API: {0}", sdrplay_api_GetErrorString(err));
                return;
            }
            _this->initOk = true;
        }

        sdrplay_api_LockDeviceApi();
        sdrplay_api_DeviceT devArr[MAX_DEV_COUNT];
        unsigned int numDev = 0;
        sdrplay_api_GetDevices(devArr, &numDev, MAX_DEV_COUNT);
        for (unsigned int i = 0; i < numDev; i++) {
            if (std::string(devArr[i].SerNo) == std::string(_this->openDev.SerNo)) {
                _this->openDev = devArr[i];
                break;
            }
        }
        _this->openDev.tuner = sdrplay_api_Tuner_A;
        _this->openDev.rspDuoMode = sdrplay_api_RspDuoMode_Single_Tuner;
        err = sdrplay_api_SelectDevice(&_this->openDev);
        sdrplay_api_UnlockDeviceApi();
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not select RSP device: {0}", errStr);
            sdrplay_api_Close();
            _this->initOk = false;
            return;
        }

        sdrplay_api_DebugEnable(_this->openDev.dev, sdrplay_api_DbgLvl_Disable);

        err = sdrplay_api_GetDeviceParams(_this->openDev.dev, &_this->openDevParams);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not get device params for RSP device: {0}", errStr);
            sdrplay_api_ReleaseDevice(&_this->openDev);
            sdrplay_api_Close();
            _this->initOk = false;
            return;
        }

        err = sdrplay_api_Init(_this->openDev.dev, &_this->cbFuncs, _this);
        if (err != sdrplay_api_Success) {
            const char* errStr = sdrplay_api_GetErrorString(err);
            flog::error("Could not init RSP device: {0}", errStr);
            sdrplay_api_ReleaseDevice(&_this->openDev);
            sdrplay_api_Close();
            _this->initOk = false;
            return;
        }' \
          --replace-fail \
            '        // Release device after stopping
        sdrplay_api_Uninit(_this->openDev.dev);
        sdrplay_api_ReleaseDevice(&_this->openDev);' \
            '        // Release device and close API after stopping
        sdrplay_api_Uninit(_this->openDev.dev);
        sdrplay_api_ReleaseDevice(&_this->openDev);
        if (_this->initOk) {
            sdrplay_api_Close();
            _this->initOk = false;
        }'

        # LimeSDR source: defer probing to menuSelected, fix NULL deref if busy, and clear devNames
        substituteInPlace source_modules/limesdr_source/src/main.cpp \
          --replace-fail \
            '        refresh();

        // Select device from config
        selectFirst();

        sigpath::sourceManager.registerSource("LimeSDR", &handler);' \
            '        sigpath::sourceManager.registerSource("LimeSDR", &handler);' \
          --replace-fail \
            '    void refresh() {
        devCount = LMS_GetDeviceList(devList);
        char buf[256];
        devListTxt = "";

        for (int i = 0; i < devCount; i++) {
            lms_device_t* dev = NULL;
            LMS_Open(&dev, devList[i], NULL);
            const lms_dev_info_t* info = LMS_GetDeviceInfo(dev);
            sprintf(buf, "%s [%" PRIX64 "]", info->deviceName, info->boardSerialNumber);
            LMS_Close(dev);

            devNames.push_back(buf);
            devListTxt += buf;
            devListTxt += '\'''\0'\''';
        }
    }' \
            '    void refresh() {
        devCount = LMS_GetDeviceList(devList);
        char buf[256];
        devNames.clear();
        devListTxt = "";

        for (int i = 0; i < devCount; i++) {
            lms_device_t* dev = NULL;
            if (LMS_Open(&dev, devList[i], NULL) == 0 && dev != NULL) {
                const lms_dev_info_t* info = LMS_GetDeviceInfo(dev);
                if (info != NULL) {
                    sprintf(buf, "%s [%" PRIX64 "]", info->deviceName, info->boardSerialNumber);
                }
                else {
                    snprintf(buf, sizeof(buf), "%s", devList[i]);
                }
                LMS_Close(dev);
            }
            else {
                snprintf(buf, sizeof(buf), "%s", devList[i]);
            }

            devNames.push_back(buf);
            devListTxt += buf;
            devListTxt += '\'''\0'\''';
        }
    }' \
          --replace-fail \
            '    void selectByName(std::string name) {
        for (int i = 0; i < devCount; i++) {
            if (devNames[i] == name) {
                selectByInfoStr(devList[i]);
                break;
            }
        }
        selectFirst();
    }' \
            '    void selectByName(std::string name) {
        for (int i = 0; i < devCount; i++) {
            if (devNames[i] == name) {
                selectByInfoStr(devList[i]);
                return;
            }
        }
        selectFirst();
    }' \
          --replace-fail \
            '        lms_device_t* dev = NULL;
        LMS_Open(&dev, info, NULL);

        channelCount = LMS_GetNumChannels(dev, false);
        char buf[32];' \
            '        lms_device_t* dev = NULL;
        if (LMS_Open(&dev, info, NULL) != 0 || dev == NULL) {
            selectedDevName = "";
            return;
        }

        channelNamesTxt = "";
        channelCount = LMS_GetNumChannels(dev, false);
        char buf[32];' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        LimeSDRSourceModule* _this = (LimeSDRSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("LimeSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        LimeSDRSourceModule* _this = (LimeSDRSourceModule*)ctx;
        if (!_this->running && _this->selectedDevName.empty()) {
            _this->refresh();
            config.acquire();
            std::string devName = config.conf.contains("device") && config.conf["device"].is_string()
                ? std::string(config.conf["device"])
                : "";
            config.release();
            _this->selectByName(devName);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("LimeSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
          --replace-fail \
            '        // Open device
        _this->openDev = NULL;
        LMS_Open(&_this->openDev, _this->devList[_this->devId], NULL);
        int err = LMS_Init(_this->openDev);

        // On open fail, retry (work around for LimeSuite bug)
        if (err) {
            LMS_Close(_this->openDev);
            LMS_Open(&_this->openDev, _this->devList[_this->devId], NULL);
            if (err = LMS_Init(_this->openDev)) {
                flog::error("Failed to re-initialize device ({})", err);
                return;
            }
        }' \
            '        // Open device
        _this->openDev = NULL;
        if (LMS_Open(&_this->openDev, _this->devList[_this->devId], NULL) != 0 || _this->openDev == NULL) {
            flog::error("Could not open LimeSDR device");
            return;
        }
        int err = LMS_Init(_this->openDev);

        // On open fail, retry (work around for LimeSuite bug)
        if (err) {
            LMS_Close(_this->openDev);
            _this->openDev = NULL;
            if (LMS_Open(&_this->openDev, _this->devList[_this->devId], NULL) != 0 || _this->openDev == NULL) {
                flog::error("Could not reopen LimeSDR device");
                return;
            }
            if (err = LMS_Init(_this->openDev)) {
                flog::error("Failed to re-initialize device ({})", err);
                LMS_Close(_this->openDev);
                _this->openDev = NULL;
                return;
            }
        }'

        # BladeRF source: defer probing to menuSelected and reset devInfoList pointer after free
        substituteInPlace source_modules/bladerf_source/src/main.cpp \
          --replace-fail \
            '        refresh();

        // Select device here
        config.acquire();
        std::string serial = config.conf["device"];
        config.release();
        selectBySerial(serial);

        sigpath::sourceManager.registerSource("BladeRF", &handler);' \
            '        sigpath::sourceManager.registerSource("BladeRF", &handler);' \
          --replace-fail \
            '        if (devInfoList != NULL) {
            bladerf_free_device_list(devInfoList);
        }' \
            '        if (devInfoList != NULL) {
            bladerf_free_device_list(devInfoList);
            devInfoList = NULL;
        }' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        BladeRFSourceModule* _this = (BladeRFSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("BladeRFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        BladeRFSourceModule* _this = (BladeRFSourceModule*)ctx;
        if (!_this->running && _this->selectedSerial.empty()) {
            _this->refresh();
            config.acquire();
            std::string serial = config.conf["device"];
            config.release();
            _this->selectBySerial(serial);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("BladeRFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # Airspy source: defer probing to menuSelected
        substituteInPlace source_modules/airspy_source/src/main.cpp \
          --replace-fail \
            '        refresh();
        if (sampleRateList.size() > 0) {
            sampleRate = sampleRateList[0];
        }

        // Select device from config
        config.acquire();
        std::string devSerial = config.conf["device"];
        config.release();
        selectByString(devSerial);

        sigpath::sourceManager.registerSource("Airspy", &handler);' \
            '        sigpath::sourceManager.registerSource("Airspy", &handler);' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        AirspySourceModule* _this = (AirspySourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AirspySourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        AirspySourceModule* _this = (AirspySourceModule*)ctx;
        if (!_this->running && _this->selectedSerial == 0) {
            _this->refresh();
            config.acquire();
            std::string devSerial = config.conf["device"];
            config.release();
            _this->selectByString(devSerial);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AirspySourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # Airspy HF+ source: defer probing to menuSelected
        substituteInPlace source_modules/airspyhf_source/src/main.cpp \
          --replace-fail \
            '        refresh();

        config.acquire();
        std::string devSerial = config.conf["device"];
        config.release();
        selectByString(devSerial);

        sigpath::sourceManager.registerSource("Airspy HF+", &handler);' \
            '        sigpath::sourceManager.registerSource("Airspy HF+", &handler);' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        AirspyHFSourceModule* _this = (AirspyHFSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AirspyHFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        AirspyHFSourceModule* _this = (AirspyHFSourceModule*)ctx;
        if (!_this->running && _this->selectedSerial == 0) {
            _this->refresh();
            config.acquire();
            std::string devSerial = config.conf["device"];
            config.release();
            _this->selectByString(devSerial);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AirspyHFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # RTL-SDR source: defer probing to menuSelected and set devId in selectById
        substituteInPlace source_modules/rtl_sdr_source/src/main.cpp \
          --replace-fail \
            '        refresh();

        config.acquire();
        if (!config.conf["device"].is_string()) {
            selectedDevName = "";
            config.conf["device"] = "";
        }
        else {
            selectedDevName = config.conf["device"];
        }
        config.release(true);
        selectByName(selectedDevName);

        sigpath::sourceManager.registerSource("RTL-SDR", &handler);' \
            '        sigpath::sourceManager.registerSource("RTL-SDR", &handler);' \
          --replace-fail \
            '    void selectById(int id) {
        selectedDevName = devNames[id];' \
            '    void selectById(int id) {
        devId = id;
        selectedDevName = devNames[id];' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        RTLSDRSourceModule* _this = (RTLSDRSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("RTLSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        RTLSDRSourceModule* _this = (RTLSDRSourceModule*)ctx;
        if (!_this->running && _this->selectedDevName.empty()) {
            _this->refresh();
            config.acquire();
            std::string devName = config.conf["device"].is_string() ? std::string(config.conf["device"]) : "";
            config.release();
            _this->selectByName(devName);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("RTLSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # PlutoSDR source: defer probing to menuSelected and fix missing return in select()
        substituteInPlace source_modules/plutosdr_source/src/main.cpp \
          --replace-fail \
            '        // Enumerate devices
        refresh();

        // Select device
        config.acquire();
        devDesc = config.conf["device"];
        config.release();
        select(devDesc);

        // Register source' \
            '        // Register source' \
          --replace-fail \
            '        if (count < 0) {
            flog::error("Failed to enumerate contexts");
            return;
        }' \
            '        if (count < 0) {
            flog::error("Failed to enumerate contexts");
            iio_scan_context_destroy(sctx);
            return;
        }' \
          --replace-fail \
            '        // If the device is not available, select the first one
        if (!devices.keyExists(desc)) {
            select(devices.key(0));
        }

        // Update URI
        devDesc = desc;
        uri = devices.value(devices.keyId(desc));' \
            '        // If the device is not available, select the first one
        if (!devices.keyExists(desc)) {
            select(devices.key(0));
            return;
        }

        // Update URI
        devDesc = desc;
        devId = devices.keyId(desc);
        uri = devices.value(devId);' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        PlutoSDRSourceModule* _this = (PlutoSDRSourceModule*)ctx;
        core::setInputSampleRate(_this->samplerate);
        flog::info("PlutoSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        PlutoSDRSourceModule* _this = (PlutoSDRSourceModule*)ctx;
        if (!_this->running && _this->devDesc.empty()) {
            _this->refresh();
            config.acquire();
            std::string desc = config.conf["device"];
            config.release();
            _this->select(desc);
        }
        core::setInputSampleRate(_this->samplerate);
        flog::info("PlutoSDRSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # HackRF source: defer probing to menuSelected
        substituteInPlace source_modules/hackrf_source/src/main.cpp \
          --replace-fail \
            '        refresh();

        config.acquire();
        std::string confSerial = config.conf["device"];
        config.release();
        selectBySerial(confSerial);

        sigpath::sourceManager.registerSource("HackRF", &handler);' \
            '        sigpath::sourceManager.registerSource("HackRF", &handler);' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        HackRFSourceModule* _this = (HackRFSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("HackRFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        HackRFSourceModule* _this = (HackRFSourceModule*)ctx;
        if (!_this->running && _this->selectedSerial.empty()) {
            _this->refresh();
            config.acquire();
            std::string confSerial = config.conf["device"];
            config.release();
            _this->selectBySerial(confSerial);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("HackRFSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'

        # Audio source: skip registering in --server mode and defer probing to menuSelected
        substituteInPlace source_modules/audio_source/src/main.cpp \
          --replace-fail \
            '    AudioSourceModule(std::string name) {
        this->name = name;' \
            '    AudioSourceModule(std::string name) {
        this->name = name;
        if (core::args["server"].b()) { return; }' \
          --replace-fail \
            '        // Refresh devices
        refresh();

        // Select device
        std::string device = "";
        config.acquire();
        if (config.conf.contains("device")) {
            device = config.conf["device"];
        }
        config.release();
        select(device);
        
        sigpath::sourceManager.registerSource("Audio", &handler);' \
            '        sigpath::sourceManager.registerSource("Audio", &handler);' \
          --replace-fail \
            '    static void menuSelected(void* ctx) {
        AudioSourceModule* _this = (AudioSourceModule*)ctx;
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AudioSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }' \
            '    static void menuSelected(void* ctx) {
        AudioSourceModule* _this = (AudioSourceModule*)ctx;
        if (!_this->running && _this->selectedDevice.empty()) {
            _this->refresh();
            std::string device = "";
            config.acquire();
            if (config.conf.contains("device")) {
                device = config.conf["device"];
            }
            config.release();
            _this->select(device);
        }
        core::setInputSampleRate(_this->sampleRate);
        flog::info("AudioSourceModule '\'''{0}'\''': Menu Select!", _this->name);
    }'
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

      sdrppServer = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable SDR++ Server (sdrpp --server) to share non-ADS-B SDR devices over wt0 (Netbird)";
        };
        port = lib.mkOption {
          type = lib.types.port;
          default = 5259;
          description = "TCP port for SDR++ Server";
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
        after = [ "network-online.target" ] ++ lib.optional cfg.devices.sdrplay "sdrplayApi.service";
        wants = [ "network-online.target" ] ++ lib.optional cfg.devices.sdrplay "sdrplayApi.service";
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

      # SDR++ Server: low-bandwidth zstd-compressed IQ server for SDR++ clients (firewalled to wt0)
      systemd.services.sdrpp-server = lib.mkIf cfg.sdrppServer.enable {
        description = "SDR++ Server (non-ADS-B SDRs)";
        after = [ "network-online.target" ] ++ lib.optional cfg.devices.sdrplay "sdrplayApi.service";
        wants = [ "network-online.target" ] ++ lib.optional cfg.devices.sdrplay "sdrplayApi.service";
        wantedBy = [ "multi-user.target" ];
        environment = {
          HOME = "/var/lib/sdrpp-server";
          SOAPY_SDR_PLUGIN_PATH = soapyServerPluginSearchPath;
        };
        serviceConfig = {
          ExecStart = "${sdrppCustom}/bin/sdrpp --server --root /var/lib/sdrpp-server --addr 0.0.0.0 --port ${toString cfg.sdrppServer.port}";
          StateDirectory = "sdrpp-server";
          KillMode = "process";
          Restart = "on-failure";
          RestartSec = "5s";
          LimitRTPRIO = 99;
        };
      };

      # Increase socket buffer sizes for high-sample-rate IQ streaming (from soapyremote's sysctl.d)
      boot.kernel.sysctl = lib.mkIf (cfg.soapyServer.enable || cfg.sdrppServer.enable) {
        "net.core.rmem_max" = lib.mkDefault 104857600;
        "net.core.wmem_max" = lib.mkDefault 104857600;
      };

      # Restrict SoapySDRServer and SDR++ Server access strictly to the Netbird mesh interface (wt0):
      #   - TCP 55132: SoapyRemote RPC control & TCP transport
      #   - TCP 5259:  SDR++ Server compressed IQ/control stream
      #   - UDP 1900:  SoapyRemote SSDP service discovery
      #   - UDP 32768-60999: SoapyRemote ephemeral UDP IQ stream sockets allocated per stream
      networking.firewall.interfaces.wt0 = {
        allowedTCPPorts =
          lib.optional cfg.soapyServer.enable cfg.soapyServer.port
          ++ lib.optional cfg.sdrppServer.enable cfg.sdrppServer.port;
        allowedUDPPorts = lib.optional cfg.soapyServer.enable 1900;
        allowedUDPPortRanges = lib.optional cfg.soapyServer.enable {
          from = 32768;
          to = 60999;
        };
      };
    };
  };
}
