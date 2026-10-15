# Glasses Build: Parts List (3D-printed frame)

Goal: 3D-printed glasses frame, 4 mics (top-left, top-right, back-left, back-right), front camera at the brow bridge, LED indicators, all driven by one ESP32-S3.

Prices were checked on the vendor pages in October 2026 unless marked "unverified". Re-check before buying; stock and price move.

## Recommended build (~$40-45)

| Part | Pick | Qty | Price | Link | Status |
|---|---|---|---|---|---|
| MCU + camera | Seeed XIAO ESP32S3 Sense (ESP32-S3, 8MB PSRAM, 8MB flash, OV2640 camera, battery charging on board) | 1 | $13.99 | https://www.seeedstudio.com/XIAO-ESP32S3-Sense-p-5639.html | verified |
| Mics | INMP441 I2S MEMS mic module | 4 (buy a 5-pack) | ~$2-4 each | https://www.amazon.com/s?k=INMP441+microphone+module+5+pack | price unverified (EU listings were €2.6-3.75 each) |
| LEDs | Adafruit Flora NeoPixel v3, 4-pack (12.5 mm round, chainable, SK6812) | 2 packs = 8 pixels | $6.50 per pack | https://www.adafruit.com/product/1260 | verified |
| Battery | Adafruit LiPo 3.7V 500mAh (29 x 36 x 4.75 mm) | 1 | $7.95 | https://www.adafruit.com/product/1578 | verified |
| Wire, filament, misc | thin silicone wire, heat shrink, PLA/PETG | - | ~$5 | - | estimate |

No separate TP4056 charger needed: the XIAO board charges the LiPo itself (per Seeed's page).

Rough total: $13.99 + ~$10 mics + $13 LEDs + $7.95 battery = about $45. With only 4-6 pixels and a 5-pack of mics it drops to ~$38.

## Alternatives

| Part | Option | Price | Link | Notes |
|---|---|---|---|---|
| Mics | Adafruit SPH0645LM4H I2S breakout | $6.95 | https://www.adafruit.com/product/3421 | Verified. Better supported, 16.7 x 12.7 mm, L/R select pin. About $28 for 4. Known quirk on ESP32 (data is bit-shifted), check Adafruit's guide before relying on it. |
| Mics | Adafruit PDM MEMS mic breakout | $4.95 | https://www.adafruit.com/product/3492 | Verified. PDM, not I2S. Avoid: the ESP32-S3 has only one PDM RX peripheral, so it can't do 4 channels. |
| LEDs | 12-LED WS2812B ring, 37-50 mm | ~$2-6 | https://www.universal-solder.ca/product/12-led-ring-ws2812b-rgb-addressable-50mm/ | Verified (C$2.99). Too big for glasses, fine for a hat-brim or headband version. |
| Camera | Standalone OV2640 on ~75 mm flex cable, wide angle | ~$6-14 | https://kunkune.co.uk/shop/esp32-esp8266/ov2640-camera-upgrade-2mp-length-75mm/ | Verified (£5.90). Only needed if the XIAO board can't sit at the bridge and you want the camera apart from it. |

## Design notes and risks

1. Four I2S mics on one ESP32-S3 is the hard part. The chip has two I2S ports and each takes a stereo pair, so 2 mics per port = 4 total. Mic pairs share BCLK/WS and use L/R select (one mic L/R pin to GND, the other to 3.3V). The two ports must share the same BCLK/WS (one master, one slave) or the channels will drift by microseconds, which ruins direction finding. Espressif's docs confirm TDM/standard modes on both ports, but I found no finished open-source 4-mic S3 direction-of-arrival project. A Hack Club project ("Sound Direction Finder") discusses the same wiring and the same timing concern. Prototype this first on a breadboard before printing anything.
2. Espressif's own DOA component (esp_apa_doa) supports 2-4 mic arrays, but ESP-SR's DOA is only supported on ESP32-P4 per its docs. Plan to run our own GCC-PHAT, the same method the repo already uses in `pi/`.
3. Running YAMNet on the S3 is unproven. No published int8 YAMNet timing for ESP32-S3 turned up. Safest plan: the ESP32 streams 4-channel 16 kHz audio over Wi-Fi (~128 KB/s, about 1 Mbps) to a phone or laptop that runs the existing `pi/` / `demo/` pipeline. The glasses become a dumb sensor plus LED display, and the ML code is reused as is. Later, benchmark an int8 YAMNet on-device with esp-tflite-micro.
4. Wiring: mics at the four corners of the frame means 10-20 cm runs carrying clock signals at roughly 1-3 MHz. Keep wires short, twist the clock with ground, and route the data lines away from the LED data line.
5. The camera on the XIAO Sense is on a board-to-board connector, so the board itself sits at the bridge. Mounting a ~21 x 17.8 mm board plus camera at the nose will be bulky; the flex-cable OV2640 above is the fallback.
6. Power: LEDs at 5V logic/supply versus the 3.3V ESP32. SK6812 pixels run dimmer at 3.5V (per Adafruit), which is fine for a prototype. Keep brightness low to save battery.

## Sources

- Seeed XIAO ESP32S3 Sense: https://www.seeedstudio.com/XIAO-ESP32S3-Sense-p-5639.html
- Adafruit SPH0645 I2S mic: https://www.adafruit.com/product/3421
- Adafruit PDM mic: https://www.adafruit.com/product/3492
- Adafruit Flora NeoPixel 4-pack: https://www.adafruit.com/product/1260
- Adafruit LiPo 500mAh: https://www.adafruit.com/product/1578
- INMP441 EU listing (price reference): https://www.bitsandparts.nl/en/inmp441-mems-i2s-microphone-module-p1924326
- OV2640 on flex cable: https://kunkune.co.uk/shop/esp32-esp8266/ov2640-camera-upgrade-2mp-length-75mm/
- WS2812B 12-LED ring: https://www.universal-solder.ca/product/12-led-ring-ws2812b-rgb-addressable-50mm/
- ESP-IDF I2S docs (ESP32-S3): https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/i2s.html
- ESP-SR DOA docs: https://docs.espressif.com/projects/esp-sr/en/latest/esp32s3/direction_of_arrival/README.html
- Hack Club Sound Direction Finder: https://blueprint.hackclub.com/projects/9648
- ESP32 forum, two INMP441 on S3: https://esp32.com/viewtopic.php?p=116048
