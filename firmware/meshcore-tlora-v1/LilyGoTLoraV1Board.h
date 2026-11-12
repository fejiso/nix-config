#pragma once

#include <Arduino.h>
#include <helpers/ESP32Board.h>

extern const char* tlora_get_diag_name();

// LILYGO T-LoRa pre-1.0 / V1.0 board with SX1276/SX1278
class LilyGoTLoraV1Board : public ESP32Board {
public:
  void begin() {
    // Meshtastic tlora_v1 defines VEXT_ENABLE = 21 (active LOW, powers OLED & RF front-end).
    pinMode(21, OUTPUT);
    digitalWrite(21, LOW);
    delay(10);

    ESP32Board::begin();
#if defined(PIN_OLED_RESET) && (PIN_OLED_RESET >= 0)
    pinMode(PIN_OLED_RESET, OUTPUT);
    digitalWrite(PIN_OLED_RESET, HIGH);
    delay(1);
    digitalWrite(PIN_OLED_RESET, LOW);
    delay(10);
    digitalWrite(PIN_OLED_RESET, HIGH);
#endif
  }

  const char* getManufacturerName() const override {
    return tlora_get_diag_name();
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
