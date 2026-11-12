#pragma once

#include <Arduino.h>
#include <helpers/ESP32Board.h>

// LILYGO T-LoRa pre-1.0 / V1.0 board with SX1276/SX1278
class LilyGoTLoraV1Board : public ESP32Board {
public:
  const char* getManufacturerName() const override {
    return "LILYGO T-LoRa V1.0";
  }

  uint16_t getBattMilliVolts() override {
#if defined(PIN_VBAT_READ) && (PIN_VBAT_READ >= 0)
    analogReadResolution(12);

    uint32_t raw = 0;
    for (int i = 0; i < 8; i++) {
      raw += analogReadMilliVolts(PIN_VBAT_READ);
    }
    raw = raw / 8;

    return (2 * raw);
#else
    // TTGO LoRa32 pre-1.0 / V1.0 does not have an onboard battery voltage divider
    return 0;
#endif
  }

  uint32_t getIRQGpio() override {
    return P_LORA_DIO_0; // SX127x packet IRQ pin (GPIO 26)
  }
};
