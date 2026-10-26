# Week 1 tasks: software only (Thu Oct 22 – Thu Oct 29)

Parts arrive around Oct 29. Until then: no hardware, no screens. Three people: **Avery**,
**B** and **C** (fill in names). The summary and the reasoning are in `docs/team-plan.md`.
If one of us has no Mac, see the alternative split in `docs/week1-tasks-no-mac.md`.

**Goal for Thu Oct 29:** in a unit test, a siren `.wav` played through 4 simulated boxes from
135° comes out of `SoundRingKit` as a `SoundEvent` labelled `siren`, pointing back-right. The
fake box on a Mac reaches an iPhone over Bluetooth, and the firmware builds for the XIAO
ESP32-S3.

**Must** = needed this week. **Stretch** = can slide to week 2 without blocking anyone.
Revised 2026-10-22: model loading moved to C, C keeps direction for good, B's first firmware is
a minimal loudness sketch, and a two-phone body-shadow test runs before hardware arrives.

## By area

The team's planning labels, mapped to this week's tasks. Every task still has one owner; this
table is for checking that no area is forgotten.

| Area | This week | Status |
|---|---|---|
| **Hardware: 4 boxes that hear and send** | B2 firmware that builds | Software ready by Oct 29. Assembly and soldering start when parts arrive. |
| **Backend** | A5, C3, A6: the detection pipeline inside the iPhone app | There is no server. "Backend" is code on the phone, plus Firebase for settings and history only (week 2). |
| **Audio processing** | On the box: B2 (peak level), B1 (ADPCM encode). On the phone: B1 (decode), A5 (ring buffer, gate) | Covered |
| **What's fed into YAMNet** | C4 (model loading), A5 (decision rules), checked by A2 | Covered: the loudest box's audio, decoded, 16 kHz mono, the last 0.975 s, peak-normalised, every 0.1 s, skipped below −70 dBFS. A2 checks that compression doesn't hurt accuracy. A6 handles the seam when the streaming box changes. |
| **Direction and loudness** | C3, built on C2 | Covered. Loudness = dB above the loudest box's quiet level. How the app *shows* loudness is an open UI decision for week 3. |
| **Networking: boxes ↔ phone ↔ cloud** | A3 (BLE contract), B3 (fake box), B4 (iPhone receiver) | Boxes → phone covered with one fake box. Four connections at once needs real boxes (week 2). Phone → Firebase is week 2. |
| **Calibration** | A0 two-phone body-shadow test; C2 uses a placeholder value | Mostly week 2, with hardware: see "Calibration (week 2)" at the bottom. No calibration is asked of the user. |

## Calendar

| Day | Avery | B | C |
|---|---|---|---|
| Thu 22 – Fri 23 | A1 ADPCM in Python + test files | B0 loudness sketch; B3 fake box starts | **C1 repo skeleton + TFLite packaging (everyone waits on this)** |
| Sat 24 | A0 two-phone test; A2 ADPCM result | B0 done; B3 | C2 simulator |
| Sun 25 | **A3 contracts merged** (B, C approve) | review A3 | review A3 |
| Mon 26 | A4 Python fixtures | B1 ADPCM codecs; B3 done | C2 done; C4 model loading |
| Tue 27 – Wed 28 | A5 decision rules in Swift | B2 full firmware (stretch) | C4 done; C3 direction |
| Thu 29 | A6 end-to-end with C (stretch) | B4 iPhone receiver (stretch) | C3 done; A6 with Avery |

## Shared conventions (decide once, use everywhere)

- **Test fixtures** live in `fixtures/` at the repo root, so Python, Swift and the firmware's
  native tests all read the same files: `fixtures/adpcm/`, `fixtures/detector/`,
  `fixtures/direction/`.
- **ADPCM** is standard IMA ADPCM, 4 bits, **low nibble first**. One packet holds 320 samples,
  and the 4-byte state header is the encoder state *before* the packet's first sample
  (predictor int16 LE, step index uint8, pad uint8).
- **Angles:** 0° ahead, clockwise, 90° right, 180° behind, 270° left.
- **Model files** come from `ml/models/`: `yamnet_embedding_metadata.tflite`,
  `sound_head.tflite`, `labels.json`, `thresholds.json`.

---

## Avery: detection and contracts

### A0. Two-phone body-shadow test · ~1 h · due Sat 24 · Must
- Two phones recording at the same time, one on the chest and one on the back.
- Clap, then play a low sound (a car horn clip from a third phone), first from the front, then
  from behind, about 2 m away.
- Compare peak levels in Python.
- Phone auto-gain shrinks the gap, so a ≥ 6 dB difference is a real pass. A fail is
  inconclusive; retest with the boxes.
- **Done when** the result for both sounds is posted to the team.

### A1. IMA ADPCM in Python + test vectors · ~2 h · due Fri 23 · Must
- `ml/adpcm.py`: `encode(int16[]) -> bytes` and `decode(bytes, state) -> int16[]`, about 60 lines.
- Write `fixtures/adpcm/`: `input.wav` (3 s, 16 kHz mono: a sweep, a clap and silence),
  `packets.bin` (169-byte packets exactly as in the BLE contract) and `decoded.wav`.
- **Done when** decode(encode(x)) stays within ADPCM's normal error, and B has the files.

### A2. Does the classifier survive ADPCM? · ~3 h · due Sat 24 · Must
- Add `--codec adpcm` to `ml/eval_pipeline.py`. In `stream_for()`, run each clip through
  encode → decode before it reaches the detector.
- Run default against default + ADPCM. Compare caught and wrong-label rates per class at
  −20 dBFS and in the level sweep down to −50 dBFS.
- **Decision rule:** if any safety class (siren, alarm, car_horn, glass_break) loses more than
  0.05 caught, or big-label accuracy drops more than 2 points, propose a different codec
  before A3 freezes the contract.
- **Done when** a short result table is posted to the team and saved as `ml/work/eval_adpcm.md`.

### A3. Contracts in `Sources/Models/` · ~2 h · due **Sun 25** · needs C1 · Must
- Swift types from `docs/team-plan.md`: `BoxPosition`, `BoxLevel`, `SoundFrame`, `BoxSource`,
  `SoundLabel`, `FilterCategory`, `SoundEvent`, `SoundEventSource`.
- Add BLE UUIDs (B picks them), the codec from A2, and the priority table from `ml/config.py`.
- **Decide with B:** add a low-band peak (below ~500 Hz, +2 bytes) to `level`? The body blocks
  low sounds less, so direction may want it. It's cheap now and hard after the freeze.
- **Done when** the PR is merged with B and C approving.

### A4. Expected outputs from Python · ~2 h · due Mon 26 · Must
- `ml/export_fixtures.py`: run `demo/detector.py` on 30 test clips (2 per class plus 4
  "other" or background) at −20 dBFS.
- One JSON per clip in `fixtures/detector/`. For every 0.1 s hop, store `level_db`, `gated`,
  the 13 probabilities, `hits` and the big `label`.
- **Done when** the fixtures are committed and the Python detector reproduces them exactly.

### A5. Detector decision rules in Swift · ~6 h · due Wed 28 · needs A4, C4 · Must
- Builds on C4's `Classifier`, which turns audio into 13 probabilities.
- `Sources/Detection/Detector.swift`: 1 s ring buffer, 0.1 s hop, −70 dBFS gate on the loudest
  100 ms sub-window, thresholds from `thresholds.json`, persist 5, "other" veto 0.15, label
  margin 0.10 with safety classes exempt, priority × confidence × loudness score.
- `Tests/DetectionTests/DetectorFixtureTests.swift` replays every fixture.
- **Done when** every decision (gated, hits, label) matches the fixtures exactly on all 30 clips.

### A6. End-to-end test · ~3 h, with C · due Thu 29 · Stretch
- `DetectionPipeline`: `BoxSource` → direction + box switching (C3) + `Detector` (A5) →
  `SoundEventSource`.
- **Box-switch seam:** when the streaming box changes, the 1 s buffer holds audio from two boxes
  at different levels. Decide and test one rule. Either scale the new box's audio by the level
  difference so the buffer joins smoothly, or keep reporting the current event and let the
  buffer refill before a new label can fire.
- **Done when** a siren `.wav` at 135° through `WavFileBoxSource` yields a `siren` event with
  an azimuth between 90° and 180° within 1 s of simulated time, and a source that rotates past
  a box boundary keeps one event instead of flickering into two.

---

## B: boxes and input, no hardware yet

### B0. Minimal loudness sketch · ~1–2 h · due Sat 24 · Must
- `firmware/level_sketch/`: read one INMP441 on the XIAO ESP32-S3 and print peak dBFS every
  100 ms over USB serial. No Bluetooth.
- This is all the body-shadow test and the calibration checks need, so it must be ready to flash
  the day parts arrive.
- **Done when** it builds for `seeed_xiao_esp32s3`.

### B1. ADPCM in C++ and Swift · ~4 h · due Mon 26 · needs A1 · Must
- `firmware/lib/adpcm/adpcm.h/.cpp` (encoder) and `ios/Packages/SoundRingKit/Sources/Input/ADPCM.swift` (decoder).
- **Done when** the C++ encoder reproduces `fixtures/adpcm/packets.bin` byte for byte, and the
  Swift decoder reproduces `decoded.wav` sample for sample.

### B2. Full Bluetooth firmware · ~6 h · due Wed 28 · Stretch
- `firmware/platformio.ini` with two environments: `seeed_xiao_esp32s3` (Arduino) and `native`
  (for tests on your laptop).
- `src/main.cpp`:
  - I2S standard mode, 16 kHz, 32-bit slot, left channel, shifted to int16. No auto-gain;
    gain is a compile-time constant.
  - Every 100 ms: peak dBFS × 10 → `level` notify, with seq and the clipped flag.
  - NimBLE service with `level`, `audio` and `control`. Advertise `SoundBox-<SIDE>`, where the
    side comes from a build flag such as `-DBOX_SIDE=FRONT`.
  - `control` = 1 starts ADPCM `audio` notifications at 50 Hz (320 samples every 20 ms); 0 stops them.
- `test/test_level/`: a −20 dBFS sine reads −20.0 ± 0.1 dB; a full-scale square sets the clip flag.
- **Done when** `pio run -e seeed_xiao_esp32s3` builds and `pio test -e native` passes.

### B3. Fake box on a Mac · ~4 h · due Mon 26 · Must
- `tools/fake_box/`: a small macOS command-line tool (Swift, `CBPeripheralManager`) or Python
  with the `bless` library.
- Advertise `SoundBox-FRONT` with the exact contract service. Read a `.wav`, send `level` at
  10 Hz, and send ADPCM `audio` at 50 Hz while `control` = 1.
- **Done when** LightBlue on an iPhone sees it, subscribes to `level`, and writing 1 to
  `control` starts `audio`.

### B4. iPhone `Input` module · ~6–8 h · due Thu 29 · needs A3, B1, B3, C1 · Stretch
- `Sources/Input/BLEBoxSource.swift`: scan by service UUID, connect, subscribe, parse,
  decode, then emit `BoxLevel` and `SoundFrame`. `streamAudio(from:)` writes `control`.
  Reconnect on drop; count sequence gaps per box.
- Real iPhone only, since CoreBluetooth doesn't work in the Simulator.
- **Done when** 10 minutes against the fake box shows under 1% lost packets in the log, and
  the decoded audio, saved to a `.wav`, sounds like the source file.

---

## C: app skeleton, simulator and direction (no screens this week)

### C1. Repo skeleton · ~3–5 h · due **Fri 23** · Must (everyone waits on this)
- `ios/SoundRing.xcodeproj`: app target with one placeholder view. No UI work.
- `ios/Packages/SoundRingKit`: targets `Models`, `Input`, `Detection` and `Cloud` (empty),
  plus test targets.
- `ios/Config/Local.xcconfig.example` committed; `Local.xcconfig` (team ID, bundle ID suffix)
  git-ignored. Add a `.gitignore` for Xcode.
- **First thing:** confirm how TensorFlow Lite gets into the project. `TensorFlowLiteSwift` has
  historically shipped through CocoaPods, not Swift Package Manager. If there's no package
  option, decide today whether Detection uses CocoaPods or lives in the app target, and tell
  Avery. Tests that load TFLite may need to run on the iOS Simulator through `xcodebuild`
  rather than `swift test`. C owns this decision because C4 depends on it.
- **Done when** a fresh clone plus a filled-in `Local.xcconfig` builds for the Simulator and a
  device, and an empty test runs.

### C2. Four-box simulator, `WavFileBoxSource` · ~4 h · due Mon 26 · needs A3 · Must
- `Sources/Input/WavFileBoxSource.swift`, implementing `BoxSource`.
- Reads a 16 kHz mono `.wav` and takes a scripted source angle, fixed or rotating.
- **Levels:** for each box, every 100 ms, the clip's peak dB minus a body-shadow loss
  `S × (1 − cos Δ) / 2`. Δ is the angle between the box's facing (front 0°, right 90°, back
  180°, left 270°) and the source. `S` is 10 dB by default, replaced by real numbers after the
  body-shadow test. Add a −60 dBFS noise floor with ±1 dB jitter from a fixed seed.
- **Frames:** 320 samples every 20 ms, only from the box picked by `streamAudio(from:)`,
  scaled by that box's loss.
- Real-time mode for demos, fast mode for tests.
- **Done when** a test at 90° shows RIGHT loudest and LEFT about 10 dB quieter.

### C3. Direction and box switching in Swift · ~6 h · due Thu 29 · needs C2 · Must
- `Sources/Detection/Direction.swift` and `BoxSwitcher.swift`, per `docs/body-boxes-plan.md`:
  - **Quiet level per box:** the lowest 100 ms peak over the last 10 s. Freeze it while a safety
    sound is active, through a `setSafetyActive(_:)` hook that A6 wires to the detector.
  - **Loudness** = max(0, peak − quiet level), held at its peak for 0.3 s.
  - **Angle** = atan2(RIGHT − LEFT, FRONT − BACK), normalised to 0–360°. If the vector is under
    1 dB long, fall back to the loudest box's angle. If no box is 3 dB above its quiet level,
    return nil. These two thresholds aren't in the plan, so write them down.
  - **Switch** the streaming box when another box leads by ≥ 3 dB for ≥ 0.3 s.
- `Tests/DetectionTests/DirectionTests.swift`:
  - the plan's example FRONT 8, RIGHT 6, LEFT 2, BACK 1 → 29.7° ± 1°
  - BACK loudest alone → 180°
  - FRONT = BACK and LEFT = RIGHT → falls back to the loudest box
  - a 2.5 dB lead never switches; 3 dB for 0.2 s doesn't; 3 dB for 0.3 s does
  - a 30 s steady siren with the freeze on stays above 0 loudness the whole time; with it off,
    it fades
  - `WavFileBoxSource` at 135° → angle between 90° and 180°
- **Done when** all of these pass. C owns this code for good, including tuning it after the
  week-2 calibration checks. Avery reviews it.

### C4. Model loading in Swift · ~3 h · due Tue 27 · needs C1, A4 · Must
- `Sources/Detection/Classifier.swift`: load `yamnet_embedding_metadata.tflite` and
  `sound_head.tflite`, peak-normalise the last 0.975 s, run YAMNet, then the head, and return
  13 probabilities.
- **Done when** the probabilities match Avery's fixtures within 1e-4 on all 30 clips. Avery's
  decision rules (A5) build on top.

---

## Not this week
Screens, Firebase, notifications and the watch move to week 2. Background BLE mode waits for B4
to work in the foreground.

## Calibration (week 2, needs hardware)

None of this is asked of the user. It's what the team measures once and writes into code.

| Check | How | Feeds |
|---|---|---|
| Gain match | Put all 4 boxes side by side, play the same sound, compare peak levels. Any box more than 2 dB off gets a fixed trim in its firmware. | B2 gain constant |
| Body shadow | The 2-box test from `docs/body-boxes-plan.md`, with a clap **and** a low sound such as a car horn | Replaces C2's placeholder `S` = 10 dB |
| Direction accuracy | Wearer stands still; play a sound from 8 positions around them; record the angle the phone shows | Tunes C3's thresholds |
| Quiet level | 5 minutes in a quiet room and in a noisy one; check the quiet level settles and doesn't trigger | C3's 10 s window |
| Clipping | A car horn clip at 1 m from a phone speaker must not set the clip flag | B2 gain constant |
