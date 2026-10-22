# Parts list: 4 sound boxes

Goal: 4 identical clip-on boxes (FRONT, BACK, LEFT, RIGHT). Each one is an ESP32 board, one
mic, a battery and a mini breadboard in a case. How they're used: `docs/body-boxes-plan.md`.

Prices are from October 2026 and marked "unverified" where only a non-US retailer was checked.
Re-check before buying; stock and price move.

## Per box

| Part | Pick | Per box | Price | Link | Status |
|---|---|---|---|---|---|
| Board | Seeed XIAO ESP32-C3 (Bluetooth LE 5, I2S, battery charging on board) | 1 | ~$5 | https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html | unverified (UK: £4.80 at The Pi Hut) |
| Mic | INMP441 I2S MEMS mic module | 1 | ~$2–4 | https://www.amazon.com/s?k=INMP441+microphone+module+5+pack | unverified; buy a 5-pack (1 spare) |
| Battery | Adafruit LiPo 3.7 V 500 mAh (29 × 36 × 4.75 mm) | 1 | $7.95 | https://www.adafruit.com/product/1578 | verified |
| Breadboard | Mini 170-point breadboard | 1 | ~$1 | - | estimate |
| Case + clip | 3D-printed box, or a small project box, with a clothing clip or Velcro strap | 1 | ~$1–2 | - | estimate |

No separate charger: the XIAO charges the LiPo itself.

## Total for 4 boxes

4 × $5 board + ~$12 mic 5-pack + 4 × $7.95 battery + ~$4 breadboards + ~$6 cases and wire ≈
**$75**. Ask Convergent for budget or borrow parts before buying.

## Alternatives

| Part | Option | Notes |
|---|---|---|
| Board | Seeed XIAO ESP32-S3 (plain, not Sense), ~$7.50 | Works the same; use it if the team already has some. The Sense version's camera isn't needed. |
| Mic | Adafruit SPH0645LM4H I2S breakout, $6.95, https://www.adafruit.com/product/3421 | Better documented, pricier. Known ESP32 quirk: data is bit-shifted; see Adafruit's guide. |
| Battery | Smaller LiPo (250–350 mAh) | Lighter box, shorter runtime. Measure battery life on one box first. |

## Wiring (each box)

INMP441 → XIAO: VDD → 3V3, GND → GND, SCK → I2S bit clock pin, WS → I2S word select pin,
SD → I2S data in, L/R → GND (left channel). Any free GPIOs work on the C3; write the pin
numbers in the firmware config and keep them the same on all 4 boxes.

## Rules that matter

1. **Turn off auto-gain, same fixed gain on all 4 boxes.** Direction comes from comparing
   loudness, so every box must measure it the same way.
2. **Set gain so a car horn at 1 m doesn't clip.** If every box maxes out, there's no loudest
   box.
3. **Point the mic hole outward**, away from the body, so the body blocks sound from the other
   side.
4. **Build one box first, test it, then copy it 3×.** Do the 2-box body-shadow test in
   `docs/body-boxes-plan.md` before building all 4.

## Sources

- Seeed XIAO ESP32-C3: https://www.seeedstudio.com/Seeed-XIAO-ESP32C3-p-5431.html,
  UK price: https://thepihut.com/products/seeed-xiao-esp32c3
- Adafruit LiPo 500 mAh: https://www.adafruit.com/product/1578
- Adafruit SPH0645 I2S mic: https://www.adafruit.com/product/3421
- ESP-IDF I2S docs: https://docs.espressif.com/projects/esp-idf/en/latest/esp32c3/api-reference/peripherals/i2s.html
