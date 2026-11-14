# LoRa & MeshCore Project Ideas

## Hardware Inventory & Current Deployment

### Live Infrastructure
- **`hierro`**: Central controller running `owlstack-bridge` (`:9620`), `owlshack-pinto` (`:8620`), `owlshack-dublin` (`:8621`), NATS JetStream (`:4222`), VictoriaMetrics / `vmalert` / Grafana, Gatus, and `OpenClaw` (`:3080`).
- **`hispanas` (Pinto / Madrid, scope `*`)**: KISS-over-TCP modem (`:7620` over NetBird `wt0`) + plugged XIAO nRF52 repeater.
- **`lenovix` (Dublin / Ireland, scope `#ioi`)**: KISS-over-TCP modem (`:7620` over NetBird `wt0`) + solar XIAO nRF52 repeater.

### Available Hardware
- **LoRa boards & companions**:
  - MeshPocket Qi2 10Ah (daily-carry companion)
  - Heltec V3 + 18650 battery (SX1262 + OLED)
  - T-Beam v0.7 + 18650 battery (SX127x + NEO-6M GPS)
  - TTGO LoRa32 pre-1.0 & v1.0: 2x 433 MHz + 2x 868 MHz (SX1278/SX1276)
  - 4x Seeed XIAO nRF52 (1x Dublin solar repeater, 1x Pinto plugged repeater, 2x spare)
  - Handful of standalone RFM95W (SX1276 868 MHz) SPI modules
- **MCUs & SBCs**:
  - Raspberry Pi 1–3
  - RP2040 boards
  - ESP32-P4 (dual-core 400 MHz RISC-V, MIPI-DSI/CSI, 2D graphics accelerator)
  - Handful of ESP32-C3, ESP32-S3, and original ESP32
  - Endless supply of ESP8266

---

## Project Ideas

### 1. Immediate RF Upgrade + 433 MHz Dual-Band Split
- **Hardware**: **2x 868 MHz TTGO LoRa32** $\rightarrow$ swap onto `hispanas` & `lenovix`; free up the **2x 433 MHz TTGO LoRa32**.
- **Why**: Even though the SX1278 silicon tunes cleanly to `869.618 MHz`, the 433 MHz PCBs have a 433 MHz L/C front-end matching network + ~12–19 ppm crystal offset. Swapping in the two native 868 MHz TTGOs on `hispanas` and `lenovix` gains **10–20 dB of extra link budget** (unlocking more distant Madrid/Dublin repeaters directly).
- **Reuse the 2x 433 MHz TTGOs**: Run them at native **433 MHz** (superior building/foliage penetration) as a private local household link or a `433.775 MHz` LoRa APRS receiver feeding VictoriaMetrics.

---

### 2. Dublin Solar Repeater Telemetry & Winter Brownout Guard
- **Hardware**: Existing **XIAO nRF52 solar repeater (Dublin)** + **XIAO nRF52 plugged repeater (Pinto)**.
- **Idea**: Extend `owlstack-bridge` (or a lightweight NATS worker on `hierro`) to periodically query both nRF52 repeaters via MeshCore `REQ` status/telemetry frames and export `meshcore_repeater_battery_mv`, `snr_db`, `uptime_seconds`, and `rx_packets` on `:9620/metrics`.
- **Payoff**: Full LiPo charge/discharge curves through cloudy Irish winter weeks in Grafana + a `vmalert` warning before the Dublin solar node approaches cutoff.

---

### 3. Off-Grid `@claw` AI & Telegram Relay over LoRa
- **Hardware**: **MeshPocket Qi2 10Ah** in the field $\leftrightarrow$ `hispanas`/`lenovix` + **2x spare XIAO nRF52 + RFM95W** placed as hilltop/rooftop repeaters.
- **Idea**: Register a dedicated virtual MeshCore companion identity on `hierro` bridged to `OpenClaw` (`:3080`) / NATS.
- **Payoff**: When hiking off-grid in Wicklow or Sierra de Guadarrama without cell service, DM `@claw` from your MeshPocket over 868 MHz LoRa for chunked (<150-byte) AI answers, Gatus fleet checks, or urgent short message relays to Telegram.

---

### 4. Automated Coverage Heatmap / Wardriver
- **Hardware**: **T-Beam v0.7 (18650 + onboard GPS)** (+ **Heltec V3** as a portable A/B antenna test rig).
- **Idea**: Flash wardriving firmware (or MeshCore companion + logger) on the T-Beam that sends periodic `TRACE` / `PATH` probes against your Pinto and Dublin repeaters while walking/cycling/driving, recording `RSSI`, `SNR`, `FEI`, and GPS coordinates to flash.
- **Payoff**: Upload tracks over Wi-Fi into VictoriaMetrics/Grafana Geomap to spot RF shadows and choose optimal placements for your **2 remaining XIAO nRF52 + RFM95W** repeaters.

---

### 5. Out-of-Band "Break-Glass" Server Recovery over LoRa
- **Hardware**: **ESP32-S3 / C3 + RFM95W** (or **Heltec V3 with 18650** UPS) wired to `hispanas` / `lenovix` UART console + reset/smart-plug relay.
- **Idea**: Listen for Ed25519-authenticated MeshCore `REQ` commands from your allowlisted companions.
- **Payoff**: If home fiber, router, or NetBird `wt0` wedges, send a signed LoRa command to restart `netbird`, read the last few lines of `dmesg` / `systemctl --failed`, or power-cycle the ISP router completely out-of-band.

---

### 6. Wall-Mounted "MeshDeck" NOC Display (`blinkenlights` Pro)
- **Hardware**: **ESP32-P4** + **ESP32-C3** (SDIO/UART Wi-Fi co-processor) + **RFM95W** over SPI.
- **Idea**: Drive a crisp wall display combining Gatus fleet health (`blinkenlights` big brother) with a live Pinto $\leftrightarrow$ Dublin MeshCore packet waterfall, `#maddub` ticker, and solar repeater gauges from `hierro` NATS — plus a local `RFM95W` fallback so it switches to direct 868 MHz RF monitoring if internet/Wi-Fi drops.

---

### 7. Attic/Mast Remote Radio Heads (Zero Coax Loss) & Dual-Protocol Sniffer
- **Hardware**: **Raspberry Pi 1–3** (or **RP2040 USB-CDC KISS dongle** + Pi) + **1–2x RFM95W**.
- **Idea**: At 868 MHz, a few meters of thin coax eats half your TX/RX power. Mount a Pi + `RFM95W` right at the roof/attic antenna feedpoint speaking `KISS-over-TCP :7620` over Wi-Fi/Ethernet directly to `owlstack-bridge`.
- **Bonus**: Wire a **second `RFM95W`** to the same Pi (`CE1`) on `869.525 MHz` (`EU_868` Meshtastic) alongside `869.618 MHz` (MeshCore EU/UK Narrow) to observe both local meshes simultaneously from one mast.

---

### 8. ESP8266 ESP-NOW $\rightarrow$ LoRa Sensor Swarm
- **Hardware**: **Endless ESP8266s** + **1x ESP32 + RFM95W** concentrator.
- **Idea**: Full Wi-Fi association drains batteries on ESP8266, *but* raw **ESP-NOW** wakes in ~20 ms, transmits a 30-byte temperature/humidity/door/leak/mains-power packet, and returns to deep sleep for months. A single wall-powered ESP32+RFM95W aggregates all ESP-NOW frames into `hierro` NATS/VictoriaMetrics, falling back to LoRa (`#maddub` / DM alert) during a power or fiber outage.
