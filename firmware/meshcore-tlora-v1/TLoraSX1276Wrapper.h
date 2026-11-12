#pragma once

#include <helpers/radiolib/CustomSX1276Wrapper.h>

// Minimal wrapper over CustomSX1276Wrapper so kiss_modem behaves identically
// to simple_repeater / companion_radio on TTGO LoRa32 V1.0 (SX1276/SX1278):
//
// 1. Do NOT touch RegOpMode LowFrequencyModeOn (bit 3): on 433 MHz TTGO LoRa32
//    boards operated at 868 MHz, the physical antenna trace is wired to RFI_LF
//    (not RFI_HF), so RadioLib's default RegOpMode (identical to repeater &
//    Meshtastic) must be preserved.
// 2. CustomSX1276Wrapper::setParams() and RadioLibWrapper::setTxPower() put the
//    SX1276 into STANDBY without resetting RadioLibWrapper's static `state` from
//    STATE_RX; in simple_repeater those run once before STATE_RX is ever entered,
//    whereas kiss_modem receives HW_CMD_SET_RADIO / HW_CMD_SET_TX_POWER later
//    from the host. Call idle() + startRecv() so RXCONTINUOUS resumes immediately.
// 3. Disable kiss_modem's hardcoded 30s resetAGC() (_radio->sleep()), matching
//    simple_repeater / companion_radio where agc_reset_interval defaults to 0.
// 4. Wait 15 ms after entering RXCONTINUOUS before sampling REG_RSSI_VALUE so
//    initial 0-reads (-157 dBm) do not lock _noise_floor at -120 dBm.
class TLoraSX1276Wrapper : public CustomSX1276Wrapper {
  static constexpr uint32_t RX_RSSI_SETTLE_MS = 15;
  uint32_t _rx_settle_until_ms = 0;
  uint32_t _prev_recv = 0;
  uint32_t _prev_err = 0;
  uint16_t _last_hdr_reg = 0;
  uint16_t _hdr_total = 0;
  int32_t _last_fei_hz = 0;
  int16_t _last_pkt_rssi = 0;
  int8_t _last_pkt_snr_q4 = 0;

  void resetNoiseFloorTracking() {
    _noise_floor = 0;
    _num_floor_samples = 0;
    _floor_sample_sum = 0;
    _rx_settle_until_ms = millis() + RX_RSSI_SETTLE_MS;
  }

  uint16_t readHdrReg() const {
    Module* m = ((CustomSX1276*)_radio)->getMod();
    return ((uint16_t)m->SPIreadRegister(0x14) << 8) | m->SPIreadRegister(0x15);
  }

  void sampleRxDiagnostics(bool forceLatch) {
    CustomSX1276* sx = (CustomSX1276*)_radio;
    uint16_t hdr_reg = readHdrReg();
    bool new_hdr = false;
    if (hdr_reg > _last_hdr_reg) {
      _hdr_total += (hdr_reg - _last_hdr_reg);
      new_hdr = true;
    }
    _last_hdr_reg = hdr_reg;

    if (forceLatch || new_hdr) {
      _last_fei_hz = (int32_t)sx->getFrequencyError(false);
    }
    if (forceLatch) {
      _last_pkt_rssi = (int16_t)sx->getRSSI();
      _last_pkt_snr_q4 = (int8_t)(sx->getSNR() * 4.0f);
    }
  }

protected:
  void doResetAGC() override {
    // No-op on SX1276 (matches simple_repeater agc_reset_interval = 0).
  }

public:
  TLoraSX1276Wrapper(CustomSX1276& radio, mesh::MainBoard& board)
    : CustomSX1276Wrapper(radio, board) { }

  void begin() override {
    CustomSX1276Wrapper::begin();
    resetNoiseFloorTracking();
  }

  void resetAGC() override {
    // No-op on SX1276: avoid periodic _radio->sleep() RX dropouts in kiss_modem.
  }

  void setParams(float freq, float bw, uint8_t sf, uint8_t cr) override {
    CustomSX1276Wrapper::setParams(freq, bw, sf, cr);
    // Restore RXCONTINUOUS immediately instead of leaving SX1276 in STANDBY.
    idle();
    startRecv();
    _last_hdr_reg = readHdrReg();
    resetNoiseFloorTracking();
  }

  // Called via `extern WRAPPER_CLASS radio_driver;` in kiss_modem/companion/repeater.
  void setTxPower(int8_t dbm) {
    // SX1278::setOutputPower() on PA_BOOST accepts 2..17 or 20 dBm (18..19 fail).
    if (dbm > 20) dbm = 20;
    else if (dbm > 17 && dbm < 20) dbm = 17;
    else if (dbm < 2) dbm = 2;

    RadioLibWrapper::setTxPower(dbm);
    // setOutputPower() drops SX1276 into STANDBY; return to RXCONTINUOUS immediately.
    idle();
    startRecv();
    _last_hdr_reg = readHdrReg();
    _rx_settle_until_ms = millis() + RX_RSSI_SETTLE_MS;
  }

  int recvRaw(uint8_t* bytes, int sz) override {
    bool was_rx = isInRecvMode();
    int len = CustomSX1276Wrapper::recvRaw(bytes, sz);
    if (n_recv != _prev_recv || n_recv_errors != _prev_err) {
      _prev_recv = n_recv;
      _prev_err = n_recv_errors;
      sampleRxDiagnostics(true);
    }
    if (!was_rx && isInRecvMode()) {
      _last_hdr_reg = readHdrReg();
      _rx_settle_until_ms = millis() + RX_RSSI_SETTLE_MS;
    }
    return len;
  }

  void loop() override {
    if (isInRecvMode()) {
      sampleRxDiagnostics(false);
    }
    if ((int32_t)(millis() - _rx_settle_until_ms) < 0) {
      return;
    }
    if (_num_floor_samples < 64 && getCurrentRSSI() <= -155.0f) {
      return;
    }
    CustomSX1276Wrapper::loop();
  }

  void formatDiag(char* buf, size_t sz) const {
    CustomSX1276* sx = (CustomSX1276*)_radio;
    Module* m = sx->getMod();
    uint8_t ver = m->SPIreadRegister(0x42);
    uint8_t op = m->SPIreadRegister(0x01);
    uint32_t frf = ((uint32_t)m->SPIreadRegister(0x06) << 16)
                 | ((uint32_t)m->SPIreadRegister(0x07) << 8)
                 | (uint32_t)m->SPIreadRegister(0x08);
    uint8_t pa = m->SPIreadRegister(0x09);
    uint8_t lna = m->SPIreadRegister(0x0C);
    uint8_t mc1 = m->SPIreadRegister(0x1D);
    uint8_t mc2 = m->SPIreadRegister(0x1E);
    uint8_t mc3 = m->SPIreadRegister(0x26);
    uint8_t rr = m->SPIreadRegister(0x1B);
    uint8_t irq = m->SPIreadRegister(0x12);
    uint8_t ms = m->SPIreadRegister(0x18);
    snprintf(
      buf, sz,
      "TLoraV1 v=%02x op=%02x frf=%06lx pa=%02x lna=%02x mc=%02x/%02x/%02x rr=%u irq=%02x ms=%02x hdr=%u fei=%ld sr=%d/%d",
      ver, op, (unsigned long)frf, pa, lna, mc1, mc2, mc3, rr, irq, ms,
      (unsigned)_hdr_total, (long)_last_fei_hz, (int)_last_pkt_snr_q4, (int)_last_pkt_rssi
    );
  }
};
