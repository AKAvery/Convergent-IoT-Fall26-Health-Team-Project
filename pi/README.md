# Sound Ring — real-life "visualize sound effects"

A hat-brim / headband wearable that lights an LED ring in the direction of a
sound, coloured by what the sound is. Raspberry Pi + ReSpeaker 4-Mic HAT + YAMNet embeddings + our trained head.

## Parts (~$60–75)

| Part | Approx. price | Notes |
|---|---|---|
| Raspberry Pi Zero 2 W | $15 | Pi 4 works too and is faster (~2× YAMNet rate) |
| Seeed ReSpeaker 4-Mic Array for Raspberry Pi | $25–30 | 4 mics + 12 built-in RGB LEDs. Everything you need on one board |
| microSD card, 16 GB+ | $6 | |
| USB power bank, 5 V / 2 A | $10–15 | Any small one; a few hours of runtime |
| Headband or cap + zip ties / velcro | $5 | Mount the HAT flat on top, mics up |
| Mic foam / fur windscreen (optional) | $5 | Big help outdoors |

Prices move around; check Seeed Studio, Adafruit, or Amazon.

## Setup (once)

1. Flash Raspberry Pi OS Lite (64-bit) and boot with SSH enabled.
2. Install the ReSpeaker driver:
   ```bash
   sudo apt update && sudo apt install -y git
   git clone https://github.com/HinTak/seeed-voicecard   # maintained fork of Seeed's driver
   cd seeed-voicecard && sudo ./install.sh && sudo reboot
   ```
   After reboot, `arecord -l` should list `seeed-4mic-voicecard`.
3. Enable SPI (for the LEDs): `sudo raspi-config` → Interface Options → SPI → Yes.
4. Python deps:
   ```bash
   sudo apt install -y python3-pip python3-numpy python3-spidev libportaudio2
   pip3 install --break-system-packages sounddevice tflite-runtime
   ```
5. The models are already in this folder: `yamnet_embedding_metadata.tflite` (Google's
   backbone) and `sound_head.tflite` + `labels.json` (ours, trained in `../ml`).

## Run

```bash
python3 sound_ring.py
```

You'll see a line per detection, e.g.

```
dog                       0.91    95°  -31.2 dB   | cat, other
```

and the LED nearest 95° (roughly to your right) lights orange.

## Calibrate direction

Stand in a quiet room, clap from directly in front of the board (the side with
the USB/HDMI ports if the HAT is seated normally), and watch which LED lights.
Change `CALIBRATION_OFFSET_DEG` in `sound_ring.py` until LED 0 lights for a
front clap. If left/right are mirrored, swap the sign of `y` in `estimate_angle`.

## Tune it

- `HIGHLIGHT` — label -> LED colour. Labels come from `labels.json` (trained in `../ml`).
- `LOUDNESS_GATE_DB` — raise toward -35 if it flickers on room noise.
- `MIN_CONFIDENCE` — raise toward 0.4 for fewer false positives.
- `IGNORE` — add your own voice-y classes if it keeps firing on you talking.

## Known limits

- Direction is ±15–30° for sharp sounds; vague for hums and distant traffic.
- Distance isn't measured (the ring only shows direction). LED brightness could
  be tied to `level_db` if you want a rough loudness cue.
- Indoors, strong echoes can point at a wall instead of the source.
- About 0.5 s latency on a Pi Zero 2; faster on a Pi 4.
- Mount the board flat with mics facing up; angles assume the board is level.

## Next steps

- Add an IMU (~$3, MPU-6050) so the lit LED stays locked to the world direction as you turn your head.
- Train a small custom model on Edge Impulse for 5–10 sounds you actually care about; faster and more accurate than YAMNet's 521 classes.
- Swap the ring for a short LED strip inside glasses frames for a glance-level peripheral cue.
