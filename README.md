# Sound Ring

Fortnite's "visualize sound effects," in real life.

3D-printed glasses that hear, locate and name the sounds around you, then show them on your
Apple Watch as arrows around a bird's-eye view of you, with a full iPhone app behind it. Built
for people who are deaf or hard of hearing, and for anyone who wants sound awareness (safety,
privacy, babies). Texas Convergent IoT, Fall 2026.

**This README is the source of ground truth for the project.** If another doc in the repo
disagrees with it, this file wins and the other doc needs updating (see
[Docs that need reconciling](#docs-that-need-reconciling)).

**Who builds what, week by week, and the contracts between lanes:
[`docs/team-plan.md`](docs/team-plan.md).**

## What we are building

A 3D-printed glasses frame carrying:

- **4 microphones**, at the corners of the frame
- **A small battery**
- **An ESP32-S3**, which computes sound direction and streams it with one audio channel over BLE

There is **no camera** (changed 2026-10-19).

The glasses send to an **iPhone app (Swift)**, which classifies the sounds and drives an
**Apple Watch app (Swift)**:

- **Watch:** a bird's-eye view of the wearer with an arrow pointing at each sound, its label,
  loudness, and a haptic buzz for urgent sounds.
- **iPhone:** the comprehensive app. Live view, filters, settings, history, device pairing.

Example: a baby cries behind the wearer. The watch buzzes and shows a "baby cry" arrow pointing
down (behind) from the wearer icon.

```
┌──────────────────────┐  BLE: direction  ┌──────────────────────┐  WatchConnectivity  ┌───────────────────┐
│ Glasses (3D printed) │  + mono audio    │ iPhone app (Swift)   │  + notifications    │ Apple Watch app   │
│ 4 mics · ESP32-S3    │ ───────────────▶ │ classify, filter,    │ ──────────────────▶ │ bird's-eye view,  │
│ GCC-PHAT direction   │                  │ track sounds         │                     │ arrows, haptics   │
└──────────────────────┘                  └──────────┬───────────┘                     └───────────────────┘
                                                     │ async, small (not the live path)
                                                     ▼
                                   Firebase (free Spark plan):
                                   Anonymous Auth · Firestore (settings, history)
```

**Inference runs on the iPhone, not in the cloud.** Live alerts must land in about 0.3 s and keep
working with no signal. Firebase stores settings and history. The reasoning is in
`docs/team-plan.md`.

**$0 for software and services.** This is a demo: free Apple ID in Xcode (no paid Developer
Program) and Firebase Spark only (never Blaze). That rules out push, Sign in with Apple,
TestFlight, Cloud Storage and Cloud Functions; the workaround for each is in
[`docs/team-plan.md`](docs/team-plan.md#free-tier-limits). Hardware parts (~$40) are the only
cost.

## What the system derives from audio

| Attribute | Meaning | How | Where |
|---|---|---|---|
| **Direction** | where the sound is; 0° ahead, clockwise, 180° behind | Time difference of arrival across the mics (GCC-PHAT), Python version in `pi/` and `demo/` | ESP32 |
| **Type** | what the sound is (siren, baby cry, knock, speech…) | Apple's built-in sound classifier or our YAMNet + trained head (13 classes, `ml/`). Bake-off in week 1 | iPhone |
| **Loudness** | how loud it is | Level from the mic signal, calibrated later | ESP32 + iPhone |

## Sound filters

The app has filters so the wearer sees only the sound cues they care about. A filter is a set
of sound classes. Planned categories:

- **Safety**: sirens, car horns, alarms, glass breaking, and similar
- **Privacy**: speech and people nearby
- **Babies**: baby crying and related sounds
- More as user needs come in

Choosing which classes belong in each filter is a product decision driven by user needs, not a
technical one.

## Stack

| Layer | Choice |
|---|---|
| Glasses | Seeed XIAO ESP32-S3, 4× INMP441 I2S mics, LiPo; C++ on PlatformIO, `esp-dsp`, NimBLE |
| Link | BLE notifications, 50 Hz, angle + level + IMA ADPCM mono audio (packet in `docs/team-plan.md`) |
| iPhone | SwiftUI, CoreBluetooth (background mode), SoundAnalysis or TensorFlowLiteSwift, local notifications |
| Watch | SwiftUI on watchOS, WatchConnectivity, WatchKit haptics |
| Backend | Firebase Spark (free): Anonymous Auth, Firestore, Crashlytics |
| Distribution | Install from Xcode with a free Apple ID; re-install every 7 days |
| Training | Python, `ml/` (unchanged) |

## Open decisions

Owners and deadlines are in `docs/team-plan.md`.

1. Classifier: Apple built-in vs our YAMNet head
2. Final BLE packet format
3. Hardware money: Convergent budget or borrowed parts
4. How loudness is shown on the watch
5. Which sound classes go in each filter, and which are urgent
6. Whose iPhone + watch is the demo device
7. Demo date

## Repo layout

| Folder | What's in it |
|---|---|
| `demo/` | **Try it now on your laptop**: mic in, live direction ring in the browser, no hardware. See `demo/README.md`. |
| `ml/` | Training pipeline for the sound classifier. Already trained; re-run to add classes or your own recordings. See `ml/README.md`. |
| `pi/` | Earlier hat-mounted Raspberry Pi prototype. Its `gcc_phat` and classifier code are what the firmware and iPhone app port. See `pi/README.md`. |
| `docs/` | `team-plan.md` (lanes, contracts, timeline), `hardware-bom.md`, `networking.md`, mockups, project PDF, and `rendering/index.html`: an interactive 3D concept of the glasses frame. |
| `firmware/`, `ios/`, `firebase/` | To be created in week 1; see the repo layout in `docs/team-plan.md`. |

## Status

- [x] Direction of arrival from a 4-mic array (GCC-PHAT, Python)
- [x] Sound classifier: 13 classes, multi-label, 93.8% on held-out data, noise/overlap augmentation
- [x] Laptop live demo (`demo/`)
- [x] Team plan: lanes, contracts, timeline (`docs/team-plan.md`)
- [ ] Prototype 4-mic capture on the ESP32-S3 (breadboard, before printing anything)
- [ ] GCC-PHAT on the ESP32, BLE link to the iPhone
- [ ] Classifier bake-off and `Detection` module on the iPhone
- [ ] Watch app: bird's-eye view, arrows, haptics
- [ ] iPhone app: live view, filters, settings, history
- [ ] Firebase: auth, settings sync, history
- [ ] Design and 3D-print the glasses frame
- [ ] Test on real hardware and calibrate loudness
- [ ] Record our own clips (doorbell, dryer, smoke alarm, baby cry) and retrain

## Docs that need reconciling

Written before the 2026-10-19 change. Treat these as reference until updated:

- `docs/networking.md` recommends Wi-Fi + UDP and Flutter. Now BLE (iOS background) and
  native Swift, with direction computed on the ESP32. Its latency numbers still apply.
- `docs/hardware-bom.md` lists the XIAO **Sense** (camera) and LED indicators. Neither is
  needed now: plain XIAO ESP32-S3, no LEDs.
- `docs/rendering/index.html` models a bridge camera.
- `docs/mockup.svg`, `clip_mockup.svg`, `pov_mockup.svg`, `pi/` and the project PDF describe
  older directions (LED ring, phone video overlay).
