# Sound Ring

Fortnite's "visualize sound effects," in real life.

3D-printed smart glasses that hear, locate and name the sounds around you, then show them as
text and symbols laid over a live video view, positioned by where each sound came from. Built
for people who are deaf or hard of hearing, and for anyone who wants sound awareness (safety,
privacy, babies). Texas Convergent IoT, Fall 2026.

**This README is the source of ground truth for the project.** If another doc in the repo
disagrees with it, this file wins and the other doc needs updating (see
[Docs that need reconciling](#docs-that-need-reconciling)).

## What we are building

A 3D-printed glasses frame carrying:

- **4+ microphones**, at the corners of the frame
- **A camera** at the bridge of the nose
- **A small battery**, attached to the frame
- **A microcontroller** (ESP32 or something smaller), chosen to fit the product and to
  minimise both cost and time latency

The frame captures audio and video and sends both to a **phone**. The phone does all the
processing and does two things:

1. **Live-streams the camera video with minimal delay.**
2. **Overlays text or symbols on that stream** showing where each identifiable sound is coming
   from, in the cardinal direction of the sound relative to the wearer.

Example: a baby cries behind the wearer. The app shows "baby cry" at the **bottom** of the
screen, because behind = bottom. Left and right sounds appear at the screen's left and right
edges; sounds in front appear in the middle of the view.

The phone app is a **proof-of-concept mockup** of what the wearer would see through their
lenses on a live display like Meta's glasses. It is not the final product surface.

```
┌─────────────────────────────┐   audio + video    ┌──────────────────────────────────┐
│  Glasses frame (3D printed) │ ─────────────────▶ │  Phone app                       │
│  4+ mics · bridge camera    │      wireless      │  • live video, minimal delay     │
│  MCU · small battery        │                    │  • direction / type / loudness   │
└─────────────────────────────┘                    │  • overlay: "baby cry" at bottom │
                                                   └──────────────────────────────────┘
```

**Stretch goal (if we finish early):** remove the camera and put a mini projector in its place,
so the overlay is shown inside the glasses instead of on a phone.

## What the system derives from audio

Every detected sound gets three attributes:

| Attribute | Meaning | How |
|---|---|---|
| **Direction** | where the sound is, relative to the wearer | Time difference of arrival across the mics (GCC-PHAT), already implemented in `pi/` and `demo/` |
| **Type** | what the sound is (siren, baby cry, doorbell, speech…) | YAMNet embeddings + our trained head, 13 classes today, in `ml/` |
| **Volume / decibels** | how loud it is | Level measured from the mic signal; see open decisions |

## Sound filters

The app has filters so the wearer sees only the sound cues they care about. A filter is a set
of sound classes. Planned categories:

- **Safety**: sirens, car horns, alarms, glass breaking, and similar
- **Privacy**: speech and people nearby
- **Babies**: baby crying and related sounds
- More as user needs come in

Choosing which classes belong in each filter is a product decision driven by user needs, not a
technical one. The classifier can add classes by retraining the head in `ml/`.

## Open decisions

These are not settled. Each needs an owner and a call.

| # | Decision | Options / notes |
|---|---|---|
| 1 | **How to show intensity** | Size, opacity, colour, or a dB number on the symbol. Needs a calibrated level estimate; mic gain and distance both affect it. |
| 2 | **Which sound classes go in each filter** | Safety / privacy / babies lists above. Talk to users. |
| 3 | **Microcontroller** | ESP32-S3 is the working pick (see `docs/hardware-bom.md`). Optimise for cost and latency; a smaller chip is fine if it can carry 4+ I2S mics and the video link. |
| 4 | **Wireless link for audio + video** | Video forces Wi-Fi. See `docs/networking.md` for the audio path and latency budget. |
| 5 | **Where the processing runs** | Ground truth says the phone. The MCU only captures and sends. |
| 6 | **Mic count and placement** | 4+ at the corners; more mics improves direction but costs pins, wiring and battery. |

## Repo layout

| Folder | What's in it |
|---|---|
| `demo/` | **Try it now on your laptop**: mic in, live direction ring in the browser, no hardware. See `demo/README.md`. |
| `ml/` | Training pipeline for the sound classifier. Already trained; re-run to add classes or your own recordings. See `ml/README.md`. |
| `pi/` | Earlier hat-mounted prototype on a Raspberry Pi (mic array, direction finding, classification, LED ring). Its direction and classifier code is the starting point for the phone app. See `pi/README.md`. |
| `docs/` | Project overview PDF, mockups (`mockup.svg`, `clip_mockup.svg`, `pov_mockup.svg`), `hardware-bom.md`, `networking.md`, and `rendering/index.html`: an interactive 3D concept of the glasses frame (open the file directly, or `http://localhost:5050/rendering` while the demo runs). |

## Hardware

Working parts list and prices: `docs/hardware-bom.md` (roughly $40–45 for the recommended
build). Core parts: Seeed XIAO ESP32-S3 Sense (MCU + OV2640 camera), 4× INMP441 I2S MEMS mics,
a small LiPo battery.

## Status

- [x] Direction of arrival from a 4-mic array (GCC-PHAT)
- [x] Sound classifier: 13 classes, multi-label, 93.8% on held-out data, noise/overlap augmentation
- [x] Laptop live demo (`demo/`)
- [x] Hardware parts list and networking/latency plan (`docs/`)
- [ ] Prototype 4-mic capture on the chosen MCU (breadboard, before printing anything)
- [ ] Stream mic audio + camera video from the MCU to a phone
- [ ] Phone app: live video with minimal delay
- [ ] Phone app: direction/type overlay on the video
- [ ] Decide how intensity is displayed
- [ ] Sound-category filters in the app
- [ ] Design and 3D-print the glasses frame
- [ ] Test on real hardware and calibrate
- [ ] Record our own clips (doorbell, dryer, smoke alarm, baby cry) and retrain
- [ ] Stretch: replace the camera with a mini projector

## Docs that need reconciling

Written before this README. Treat these as reference until updated:

- `docs/networking.md` treats the camera as optional and describes a ring/radar UI. Under the
  ground truth the camera and live video are core, and the UI is a video overlay.
- `docs/hardware-bom.md` lists LED indicators. The ground truth has no LEDs; the display is
  the phone overlay (later, the projector).
- `docs/mockup.svg`, `clip_mockup.svg` and `pov_mockup.svg` predate the glasses-frame
  direction. Check each against this README.
- `pi/` and the original project PDF describe the hat-mounted LED ring.
