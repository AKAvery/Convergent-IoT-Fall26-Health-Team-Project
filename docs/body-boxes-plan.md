# Plan: 4 body-worn sound boxes (replaces the glasses)

Proposed 2026-10-22. Instead of one glasses frame with 4 mics, the wearer clips on **4 small
boxes**, one per side of the body. Each box is an ESP32, one mic, a battery and a mini
breadboard. The iPhone and Watch apps stay the same.

Until the README is updated, this doc describes the new hardware and how direction works.
Everything about the apps, Firebase and the $0 budget in `README.md` and `docs/team-plan.md`
still applies.

```
 FRONT box (chest)
 LEFT box (left shoulder)    ──BLE──▶  iPhone app  ──▶  Apple Watch
 RIGHT box (right shoulder)            (direction +      (arrow + label
 BACK box (upper back)                  YAMNet)           + buzz)
```

## The big idea: 4 separate ears, not one mic array

The glasses worked out direction from **tiny timing differences** between mics. That needs
mics at fixed, known distances and clocks synced to millionths of a second. Loose boxes on a
moving body can't do that, so we **don't use timing at all**.

We use **loudness** instead. Your body blocks sound like a wall, so the box facing the sound
hears it loudest.

| Question | Answer |
|---|---|
| **What** is the sound? | YAMNet, run on the iPhone, on the **loudest box only** |
| **Where** is the sound? | Compare how loud each box hears it (the tug of war below) |
| Does mic position confuse YAMNet? | No. YAMNet only names the sound and ignores where the mic is. |

## How direction works (the tug of war)

Each box pulls the arrow toward its own side, and pulls harder the louder it hears the sound.

```
sideways = RIGHT − LEFT
forward  = FRONT − BACK
angle    = atan2(sideways, forward)     // 0° = ahead, 90° = right, 180° = behind, 270° = left
```

"Loudness" here means **dB above that box's own quiet level** (see Calibration), never below
0.

**Example: a car honks at your front-right.**

| Box | Loudness above its quiet level |
|---|---|
| FRONT | 8 |
| RIGHT | 6 |
| LEFT | 2 |
| BACK | 1 |

sideways = 6 − 2 = 4, forward = 8 − 1 = 7, angle = atan2(4, 7) ≈ **30°**, so the arrow
points front-right, a bit more front.

The two loudest boxes win the tug of war on their own, and quiet boxes barely move the arrow.
With 4 boxes this gives a rough direction: good enough for "something is behind you, turn
around," not an exact angle.

**Short sounds (a clap):** each box reports its **peak** loudness over the last 0.3 s, so a
clap still lands even if the boxes' messages arrive a little out of step.

**Fallback:** if the arrow comes out tiny (for example FRONT and BACK equally loud, so they
cancel), point at the loudest box instead.

## Calibration: none for the user

| Problem | Fix | User does |
|---|---|---|
| Which box is where? | Each box is flashed with its side (FRONT / BACK / LEFT / RIGHT), advertises it in its BLE name (`SoundBox-FRONT`), and has a matching sticker | Wears each box on the side its sticker says |
| Cheap mics differ in sensitivity | The phone tracks each box's **quiet level**: the quietest it has been over the last 10 s. Loudness = current level minus that. A loud mic and a quiet mic both read "+8 dB" for the same sound. | Nothing |
| Boxes on a moving body | Direction is relative to the body anyway. The top of the Watch view = the way your chest faces. | Nothing |

Side effect of the rolling quiet level: a steady noise (a running dryer) slowly becomes "quiet"
and stops triggering. That's mostly what we want.

## Loud sounds and overlapping sounds

| Situation | What happens | Handling |
|---|---|---|
| A very loud sound from behind reaches every box | Fine. BACK still hears it loudest (body shadow), so the arrow still points back. | Nothing |
| **Auto-gain** on a mic | Each box turns its own volume up or down, so the comparison lies | **Turn auto-gain off.** Same fixed gain on all 4 boxes. This is the most important rule. |
| **Clipping** (sound so loud every mic maxes out) | Every box reads "max," so there's no winner | Set gain so a car horn at 1 m doesn't max out. Each box flags clipped frames; if several clip, the one that clipped most wins. |
| Two sounds at once (truck behind, dog in front) | The loud one drowns out the quiet one | Show the **loudest** sound only. The next one shows when it fades. |

## Inference: one box at a time

Run YAMNet on the **loudest box only**, not all 4.

- All 4 boxes hear the same sound, so 4 runs give 4 copies of the same answer.
- The loudest box has the cleanest copy, so it makes the best guess.
- It uses about 4× less battery and Bluetooth data.

**Switching boxes:** the phone switches which box streams audio only when another box has been
louder by **3 dB or more for 0.3 s**. Otherwise the stream would flip back and forth between
two nearly equal boxes.

## Full flow

```
1. All 4 boxes send one loudness number, 10× per second (tiny)
2. Phone: loudness above quiet level → tug of war → arrow angle
3. Phone tells the loudest box "send audio"; the others stay quiet
4. That box streams compressed audio → YAMNet → "car horn"
5. Watch shows "car horn ↗" and buzzes if urgent
```

## Tech stack: what to pick

Each choice in one line, then the reason in plain words.

### Box hardware

| Part | Pick | Why |
|---|---|---|
| Board | **Seeed XIAO ESP32-C3** (~$5 each, verify price) | Each box only measures loudness and compresses audio now, with no heavy math, so the cheaper C3 is enough. It has Bluetooth LE and charges a LiPo on its own. The XIAO ESP32-S3 (~$14) also works if the team already has some. |
| Mic | **1× INMP441** per box (I2S) | Same mic as before. One mic per board removes the hardest part of the glasses build (4 mics sharing one clock). |
| Battery | Small 3.7 V LiPo, 300–500 mAh | Plugs straight into the XIAO's battery pads |
| Body | Mini breadboard in a 3D-printed or off-the-shelf box with a clip | Swap to perfboard once the wiring is settled |
| Placement | Chest, upper back, left shoulder, right shoulder | Shoulders, not arms. Arms swing and would point the wrong way. |

Rough cost: 4 boxes × (~$5 board + ~$3 mic + ~$6 battery + ~$1 breadboard) ≈ **$60**, plus
cases. About $95 with S3 boards instead.

### Box → phone link

**Pick: each box connects straight to the iPhone over Bluetooth LE.**

- An iPhone can stay connected to 4 BLE devices at once, including with the phone locked in a
  pocket (`bluetooth-central` background mode, free account OK).
- Data is small: 4 × 10 loudness numbers per second, plus **one** compressed audio stream
  (~64 kbit/s). One stream is well within what iOS BLE handles.
- Rejected: a "hub" box that collects the other 3 (ESP-NOW) and talks to the phone. It's an
  extra radio protocol and an extra point of failure, for no gain at 4 boxes.

Each box has three BLE characteristics:

| Characteristic | Direction | Content |
|---|---|---|
| `level` | box → phone, notify, 10 Hz | seq (uint16), peak dB of the last 0.1 s × 10 (int16), flags (clipped, low battery) |
| `audio` | box → phone, notify, 50 Hz, **only when told to** | same 169-byte IMA ADPCM packet as `docs/team-plan.md`, azimuth field unused |
| `control` | phone → box, write | 1 = start audio, 0 = stop |

### Firmware

**Pick: C++ with Arduino-ESP32 on PlatformIO, NimBLE for Bluetooth.** Same as the glasses plan.
Arduino is the easiest ESP32 setup for a student team. One code base for all 4 boxes; the side
(FRONT, BACK, LEFT, RIGHT) is a single constant changed before flashing each box.

### iPhone, Watch, cloud, ML: unchanged

| Layer | Pick |
|---|---|
| iPhone | SwiftUI, CoreBluetooth, local notifications |
| Watch | SwiftUI on watchOS, WatchConnectivity, haptics |
| Classifier | YAMNet + our trained head (`ml/`, TensorFlowLiteSwift) or Apple's built-in SoundAnalysis. Week-1 bake-off still decides. |
| Backend | Firebase Spark (free): Anonymous Auth, Firestore |

**New on the iPhone:** the direction code moves here from the chip. It's about 30 lines of
Swift: rolling quiet level per box, peak hold, tug of war, box switching.

## What changes for each lane

| Lane | Change |
|---|---|
| 1. Hardware & Input | **Much easier.** No 4-mic clock sharing and no GCC-PHAT on the chip. Build 1 box, then copy it 3×. iPhone side now manages 4 BLE connections instead of 1. |
| 2. Detection | Adds the direction code above and box switching. Classifier work is unchanged. |
| 3. Cloud & Links | No change |
| 4. Apps | Add a "boxes" screen: 4 dots (FRONT/BACK/LEFT/RIGHT) showing connected + battery. Watch view unchanged. |

## First test (week 1, one evening)

1. Build **2** boxes on breadboards, labeled FRONT and BACK.
2. Each prints its loudness to the serial monitor.
3. Wear one on your chest and one on your back. Clap in front, then behind.
4. **Pass:** the box facing the clap reads at least 6 dB louder, every time.

If that passes, body-shadow direction works and the rest is building. If it fails, try placing
the boxes farther apart or facing outward before changing the plan.

## Docs to update if the team adopts this

- `README.md`: "What we are building," the diagram, the Direction row, Stack, Status
- `docs/team-plan.md`: Lane 1 checklist and stack, BLE packet contract (`SoundFrame` gets a box ID)
- `docs/hardware-bom.md`: new parts list for 4 boxes
- `docs/rendering/index.html`: still models the glasses
