# Parts list: 4 sound boxes

Goal: 4 identical clip-on boxes (FRONT, BACK, LEFT, RIGHT). Each one is an ESP32 board, one
mic, a battery and a mini breadboard in a case. How they're used: `docs/body-boxes-plan.md`.

## Ordered (2026-10-22)

Ordered on Amazon by Lydia Du. Order subtotal **$107.92**, before tax and shipping. Per-item
prices weren't recorded.

| Part | Exact listing | Qty ordered | Units | Needed for 4 boxes | Spare |
|---|---|---|---|---|---|
| Board | Seeed Studio XIAO ESP32-S3, plain (not Sense), 3-pack. BLE 5.0, Wi-Fi, 8 MB PSRAM, 8 MB flash, LiPo charging on board. [B0DJ6NQFKX](https://www.amazon.com/dp/B0DJ6NQFKX) | 2 packs | 6 | 4 | 2 |
| Mic | AITRIP INMP441 I2S MEMS mic module, 5-pack. [B092HWW4RS](https://www.amazon.com/dp/B092HWW4RS) | 1 pack | 5 | 4 | 1 |
| Battery | KBT 3.7 V 500 mAh LiPo, size 503035, PH 1.25 and PH 2.0 JST leads. [B0BJPG4B72](https://www.amazon.com/dp/B0BJPG4B72) | 4 | 4 | 4 | 0 |
| Breadboard | WWZMDiB mini breadboard, 170 tie points, 6-pack, with male/female jumper wires. [B09YXQJMTG](https://www.amazon.com/dp/B09YXQJMTG) | 1 pack | 6 | 4 | 2 |

**Not ordered yet:** cases and clips (3D-printed box, or a small project box with a clothing
clip or Velcro strap), and thin wire for the battery.

The boards are the **XIAO ESP32-S3**, not the ESP32-C3 the plan first picked. It does
everything a box needs (Bluetooth LE, I2S, LiPo charging) and runs the same Arduino-ESP32 and
NimBLE code. It probably draws more current than the C3, so measure battery life on one box
before trusting the 500 mAh estimate.

## Check before powering anything

1. **Battery polarity.** Generic LiPo leads don't follow one red/black convention for any
   given board. Check with a multimeter before connecting. Reversed polarity can destroy the
   board's charger.
2. **Battery connection.** The XIAO ESP32-S3 has no battery plug, only **BAT+ / BAT−** solder
   pads on the underside. Cut the JST plug off and solder the leads to the pads, or solder a
   matching JST socket to the pads.
3. **Headers.** Solder header pins on the XIAO boards and mic modules if they arrive loose.
4. **One box first.** Build and test one box end to end before soldering the other three.

## Wiring (each box)

INMP441 → XIAO: VDD → 3V3, GND → GND, SCK → I2S bit clock pin, WS → I2S word select pin,
SD → I2S data in, L/R → GND (left channel). Any free GPIOs work on the S3. Write the pin
numbers in the firmware config and keep them the same on all 4 boxes.

## Rules that matter

1. **Turn off auto-gain, same fixed gain on all 4 boxes.** Direction comes from comparing
   loudness, so every box must measure it the same way.
2. **Set gain so a car horn at 1 m doesn't clip.** If every box maxes out, there's no loudest
   box.
3. **Point the mic hole outward**, away from the body, so the body blocks sound from the other
   side.
4. **Do the 2-box body-shadow test** in `docs/body-boxes-plan.md` before building all 4.

## Alternatives (not bought)

| Part | Option | Notes |
|---|---|---|
| Board | Seeed XIAO ESP32-C3, ~$5 | The original pick. Cheaper, lower power, same code. |
| Mic | Adafruit SPH0645LM4H I2S breakout, $6.95, https://www.adafruit.com/product/3421 | Better documented, pricier. Known ESP32 quirk: data is bit-shifted; see Adafruit's guide. |
| Battery | Smaller LiPo (250–350 mAh) | Lighter box, shorter runtime. |

## Sources

- XIAO ESP32-S3 3-pack: https://www.amazon.com/dp/B0DJ6NQFKX
- AITRIP INMP441 5-pack: https://www.amazon.com/dp/B092HWW4RS
- KBT 500 mAh LiPo: https://www.amazon.com/dp/B0BJPG4B72
- WWZMDiB mini breadboard 6-pack: https://www.amazon.com/dp/B09YXQJMTG
- Seeed XIAO ESP32-S3 wiki (pinout, battery pads): https://wiki.seeedstudio.com/xiao_esp32s3_getting_started/
- ESP-IDF I2S docs (ESP32-S3): https://docs.espressif.com/projects/esp-idf/en/latest/esp32s3/api-reference/peripherals/i2s.html
