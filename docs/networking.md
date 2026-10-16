# Networking and latency

How audio gets from the frame to the phone, what it costs in delay, and why we chose
what we chose. Written 2026-10-15 for the clip-on module + phone app direction.

```
┌─────────────────────────┐   Wi-Fi (module is the AP)   ┌──────────────────────────────┐
│  Module on the frame    │   UDP, 10 ms audio blocks    │  Phone app (Flutter)         │
│  XIAO ESP32-S3 Sense    │ ───────────────────────────▶ │  ring buffer → YAMNet + head │
│  4× INMP441 I2S mics    │        ~1 Mbit/s             │  GCC-PHAT direction          │
│  (camera optional)      │                              │  ring / radar view           │
└─────────────────────────┘                              └──────────────────────────────┘
```

The module does nothing clever. It reads the mics and sends raw samples. All inference,
direction finding and UI happen on the phone. Same `.tflite` files as `pi/`.

## Latency budget

Sound onset → cue on screen. The radio link is not the bottleneck; the classifier is.

| Stage | Delay | Notes |
|---|---|---|
| Mic capture block | 10 ms | one UDP packet per block |
| Wi-Fi UDP, module → phone | 5–20 ms | **only with Wi-Fi power save off**; 100–200 ms spikes if left on |
| Classifier sees enough audio | **0.3–0.5 s median** | see measurements below; this is the real cost |
| Direction (GCC-PHAT) | ~50 ms of audio | can light the wedge long before the label lands |
| Inference | < 1 ms laptop CPU, 0.2–3 ms phone NPU | not a factor on a phone; ~500 ms on a Pi Zero 2 |
| Draw | ~16 ms | one display frame; push state, don't poll |

Expected on the phone: direction in ~0.1 s, label in ~0.3 s median, ~0.6 s typical worst case.
The link adds roughly 30–50 ms on top of what the laptop demo already does.

### Measured: how long after onset does the classifier fire?

Offline simulation of the `demo/live_demo.py` loop on 120 ESC-50 clips of our classes,
2 s of quiet prepended, timed from onset to first fire. Thresholds from `pi/thresholds.json`,
`-50 dB` loudness gate as in the demo. Laptop CPU, TFLite + XNNPACK.

| hop | persist | median | p90 | missed |
|---|---|---|---|---|
| 0.25 s (demo today) | 2 | 0.50 s | 1.05 s | 1 |
| 0.25 s | 1 | 0.25 s | 0.75 s | 0 |
| **0.10 s** | **2** | **0.30 s** | **0.81 s** | **0** |
| 0.10 s | 1 | 0.20 s | 0.61 s | 0 |
| 0.05 s | 1 | 0.18 s | 0.61 s | 0 |

Inference per 1 s window: 0.6 ms median. The classifier fires from the first fraction of a
sound inside its 0.975 s window; it does not need the window full. Caveats: clean clips, some
overlap the training set, and false positives on real background noise were not measured.

### Getting it down (in order of payoff per effort)

1. **Hop 0.1 s, persist 2.** 0.50 → 0.30 s median, no extra misses. 10 inferences/s is trivial on a phone.
2. **Split direction from label.** Draw the wedge from GCC-PHAT at onset; colour it when the label arrives.
3. **Per-class persistence.** persist 1 for alarm / siren / car_horn / glass_break; persist 2 for the
   classes that flicker on room noise (dog, speech, footsteps, appliance). Verify false positives first.
4. **Push, don't poll.** The demo page polls every 150 ms; that is 0–150 ms of pure display delay.
5. **Small UDP blocks, Wi-Fi sleep off, no jitter buffer.** Append each block to the ring buffer as it
   lands. A "safety" buffer of a few hundred ms on the phone throws the whole win away.
6. **Shorter-window model** (0.5 s, custom). Would push median toward 0.15 s, but it is a retraining
   project. Last, if at all.

## Why Wi-Fi + UDP, not BLE, not WebSocket

**Bandwidth decides Wi-Fi vs BLE.** 4 mics × 16 kHz × 16-bit = 1.02 Mbit/s raw. iOS caps BLE at roughly
400–600 kbit/s in practice and it is unstable there. BLE would only work if the module computed
direction itself and sent one compressed channel, which means far more firmware on a tiny chip.
Wi-Fi carries all four raw channels with headroom and Seeed already ships an example streaming a
XIAO ESP32-S3 mic array at 1 Mbit/s over UDP. Cost: Wi-Fi with sleep disabled draws ~145 mA on an
ESP32 vs ~80–108 mA with sleep on, before mics and camera.

**UDP, not TCP/WebSocket.** TCP retransmits a lost packet and stalls everything behind it; on a flaky
2.4 GHz link that head-of-line blocking is where 200–500 ms stalls come from. Live audio wants to drop a
10 ms block and move on. WebSocket also needs an HTTP server on the ESP32 and exists so *browsers* can
hold a socket; a Flutter app opens a raw UDP socket directly. WebSocket is fine for the laptop test rig
(module → UDP → Python → browser) because the browser cannot do UDP. It is not what ships.

**Module as access point.** Phone joins the module's Wi-Fi and keeps cellular. No router, no pairing
screen, works at a demo table. BLE GATT only if we later want settings / battery level. Skip for MVP.

**Camera forces Wi-Fi.** Over BLE you get about one small JPEG per second. An ESP32-S3 does roughly
20–30 fps QVGA–VGA MJPEG over Wi-Fi; plan on 100–200 ms glass-to-glass. It adds nothing to the sound
path and roughly doubles power draw, so decide what the camera is *for* before adding it.

## Packet format

One UDP datagram per 10 ms block. 4 ch × 160 samples × 2 bytes = 1280 bytes of audio + 8-byte header
= 1288 bytes, under the 1472-byte MTU. 20 ms blocks would fragment.

```
offset  size  field
0       4     seq       uint32, increments per block; receiver detects gaps
4       2     n_ch      uint16, 4
6       2     n_samp    uint16, 160
8       1280  samples   int16 little-endian, interleaved ch0 ch1 ch2 ch3 ...
```

Receiver: append to a 1 s ring buffer per channel, never block, never request a resend, log gaps.
Module → phone: `UDP 192.168.4.1 → 192.168.4.2:12345` (ESP32 softAP defaults).

## Tech stack

| Layer | Choice | Why |
|---|---|---|
| Module MCU | Seeed XIAO ESP32-S3 Sense (~$14) | tiny, Wi-Fi+BLE, camera connector + microSD for later |
| Mics | 4× INMP441 I2S MEMS (~$3 ea) | S3 has 2 I2S ports × L/R = 4 mics, no extra chips |
| Firmware | C++, Arduino-ESP32 on PlatformIO | team ramp-up; ESP-IDF is faster but harder. Must call `WiFi.setSleep(false)` |
| Transport | softAP + raw UDP, 10 ms blocks | see above |
| App | Flutter | one codebase; UDP via `dart:io RawDatagramSocket`, no native code |
| Inference | `tflite_flutter` (Google, 0.12.1) | loads `pi/*.tflite` unchanged; CoreML/Metal on iOS, NNAPI/GPU on Android |
| Direction | port `gcc_phat` from `pi/sound_ring.py` to Dart, FFT via `fftea` | ~40 lines |
| UI | CustomPainter ring, port of the demo's SVG wedge | state via Stream from an audio isolate, no polling |
| Training | unchanged: Python, `ml/` | retrain the head when we record our own clips |

Escape hatches: all-iPhone team with Swift skills → native Swift, Network.framework, TensorFlowLiteSwift.
React Native team → `react-native-udp` + `react-native-fast-tflite`. Neither unless team skill forces it.

## Build order

1. Module streams UDP to a laptop; `arecord`-style dump to `.wav` to check the mics.
2. Point `demo/live_demo.py` at the UDP socket instead of the laptop mic. Proves hardware, link and
   latency with zero app code. Browser stays as the display.
3. Measure UDP round-trip with power save off, and TFLite time on the demo phone. These are the two
   numbers above that are estimates rather than measurements.
4. Flutter app replaces the laptop.

## Sources

Numbers above are vendor docs and forum reports unless marked measured.

- iOS BLE throughput: [Apple forum, ~500 kbps at 15 ms](https://developer.apple.com/forums/thread/713349),
  [Punch Through, packets per connection event](https://punchthrough.com/maximizing-ble-throughput-on-ios-and-android/),
  [Espressif FAQ, BLE up to 700 kbps](https://github.com/espressif/esp-faq/blob/a71fa4f/docs/en/software-framework/ble-bt.rst)
- Wi-Fi audio: [Espressif i2s_mic UDP example](https://components.espressif.com/components/embedblocks/i2s_mic/versions/0.2.1/examples/wifi_audio_tx),
  [Seeed XIAO ESP32-S3 + ReSpeaker UDP stream](https://wiki.seeedstudio.com/respeaker_xvf3800_xiao_udp_audio_stream)
- Power save latency: [esp32.com](https://esp32.com/viewtopic.php?p=47850),
  [arduino-esp32 #1484](https://github.com/espressif/arduino-esp32/issues/1484),
  [Mischianti, power modes and current](https://mischianti.org/esp32-practical-power-saving-manage-wifi-and-cpu-1)
- Phone inference: [Qualcomm YAMNet benchmarks](https://huggingface.co/qualcomm/YamNet)
- Camera: [hx-esp32-cam-fpv, 90–110 ms](https://github.com/RomanLut/hx-esp32-cam-fpv),
  [Espressif camera solutions](https://docs.espressif.com/projects/esp-techpedia/en/latest/esp-friends/solution-introduction/camera/dvp-mipi-csi-camera-solution.html)
- App: [tflite_flutter](https://pub.dev/packages/tflite_flutter)
