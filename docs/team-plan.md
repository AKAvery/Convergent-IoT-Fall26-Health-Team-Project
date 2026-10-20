# Team plan: who builds what

Four tech members, four lanes. Each lane has one owner, a clear boundary, and a contract it
hands to the next lane. Everyone builds against **mocks** of the other lanes in weeks 2–3, so
nobody waits on anybody. Written 2026-10-19. The split is a suggestion: swap names freely,
keep the boundaries.

```
 LANE 1: Glasses & Input        LANE 2: Detection (ML)         LANE 4: Apps (UI)
┌────────────────────────┐    ┌──────────────────────────┐    ┌──────────────────────────┐
│ 4 mics → ESP32-S3      │    │ classify sound type      │    │ iPhone app (SwiftUI)     │
│ direction (GCC-PHAT)   │───▶│ thresholds, persistence  │───▶│ Watch app: bird's-eye    │
│ BLE → iPhone receiver  │    │ track sounds over time   │    │ view + arrows + haptics  │
└────────────────────────┘    └──────────────────────────┘    └──────────────────────────┘
        SoundFrame                     SoundEvent                       ▲
                                           │                            │
                                           ▼                            │
                              ┌──────────────────────────┐              │
                              │ LANE 3: Cloud & Links    │──────────────┘
                              │ Firebase, phone ↔ watch, │  settings, history,
                              │ notifications            │  watch updates
                              └──────────────────────────┘
```

| Lane | Owner | One-line job | Hands off |
|---|---|---|---|
| 1. Glasses & Input | _name_ | Get direction + audio from the mics onto the iPhone | `SoundFrame` stream |
| 2. Detection (ML) | _name_ | Turn audio into "siren, 90° right, loud" | `SoundEvent` stream |
| 3. Cloud & Links | _name_ | Firebase, phone → watch delivery, notifications | Settings, history, watch feed |
| 4. Apps (UI) | _name_ | Everything the user sees and touches | The product |

## Architecture decisions (settled)

- **Inference runs on the iPhone, not in Firebase.** Live alerts need to land within about
  0.3 s and must keep working with no signal. A cloud round trip adds 100–500 ms, and the device
  goes deaf in a basement. Firebase handles everything that isn't time-critical. If we want to
  show off cloud inference, that's Lane 3's stretch goal (a second-opinion model on Cloud Run),
  never the live path.
- **Glasses → phone over BLE, not Wi-Fi.** iOS suspends a backgrounded app's Wi-Fi sockets.
  BLE accessories get the `bluetooth-central` background mode, so alerts keep coming with the
  phone locked in a pocket.
- **Direction is computed on the ESP32.** Four raw channels (1 Mbit/s) don't fit through iOS
  BLE. The chip runs GCC-PHAT and sends the angle plus one compressed audio channel
  (ADPCM, about 64 kbit/s).
- **Swift everywhere on Apple.** SwiftUI for iPhone and watchOS, one Xcode project, shared
  Swift package for the contracts below.

## The contracts (agree in week 1, then freeze)

These three things are the only coupling between lanes. Change them only by a PR that all four
people approve.

### 1. BLE packet: Lane 1 → Lane 1's iPhone receiver (draft v0)

One BLE notification per 20 ms of audio. 169 bytes, fits a 185-byte iOS MTU.

```
offset  size  field
0       2     seq          uint16, wraps; receiver logs gaps
2       2     azimuth      int16, degrees × 10; -1 = no direction this frame
4       1     level        int8, dBFS of the frame (loudest mic)
5       1     flags        bit0 = onset detected, bit1 = low battery
6       3     adpcm_state  int16 predictor + uint8 step index (IMA ADPCM)
9       160   audio        320 samples, 16 kHz mono, IMA ADPCM 4-bit
```

**Angle convention (everyone uses this):** 0° = straight ahead, clockwise positive,
90° = right, 180° = behind, 270° = left.

### 2. `SoundFrame`: Lane 1 → Lane 2

```swift
struct SoundFrame: Sendable {
    let seq: UInt16
    let receivedAt: Date
    let azimuthDeg: Float?   // nil when the chip had no confident direction
    let levelDbfs: Float
    let onset: Bool
    let samples: [Int16]     // 320 samples, 16 kHz mono, already ADPCM-decoded
}

protocol SoundFrameSource {
    var frames: AsyncStream<SoundFrame> { get }
}
```

Mock: `WavFileFrameSource` plays a `.wav` from disk as frames with a fake, slowly rotating
azimuth. Lane 2 uses it until real glasses exist.

### 3. `SoundEvent`: Lane 2 → Lanes 3 and 4

```swift
enum SoundLabel: String, Codable, CaseIterable {
    case siren, alarm, glassBreak, carHorn, babyCry, knock, clap,
         dog, cat, appliance, speech, footsteps
}

enum FilterCategory: String, Codable { case safety, privacy, babies }

struct SoundEvent: Identifiable, Codable, Sendable {
    let id: UUID
    let label: SoundLabel
    var confidence: Float     // 0–1
    var azimuthDeg: Float?    // same convention as the BLE packet
    var levelDb: Float        // calibrated later; relative until then
    let startedAt: Date
    var updatedAt: Date
    var isActive: Bool        // false once the sound has stopped
    var isUrgent: Bool        // buzz the wrist even if the watch app is closed
    var categories: Set<FilterCategory>
}

protocol SoundEventSource {
    var activeEvents: AsyncStream<[SoundEvent]> { get }   // full snapshot on every change
}
```

Mock: `MockEventSource` emits scripted fake sounds from all around the wearer. Lanes 3 and 4
build entirely on it until Lane 2 is ready.

## Repo layout (Lane 4 creates the Xcode skeleton in week 1)

```
firmware/                        Lane 1   PlatformIO project for the ESP32-S3
ios/SoundRing.xcodeproj          Lane 4   targets: SoundRing (iOS), SoundRingWatch (watchOS)
ios/Packages/SoundRingKit/
    Sources/Models/              ALL      the contracts above; PR needs 4 approvals
    Sources/Input/               Lane 1   CoreBluetooth receiver, ADPCM decode, WavFileFrameSource
    Sources/Detection/           Lane 2   classifier, event tracking
    Sources/Cloud/               Lane 3   Firebase, WatchConnectivity, notifications
ios/SoundRing/, ios/SoundRingWatch/  Lane 4   SwiftUI screens
firebase/                        Lane 3   firestore.rules, storage.rules, functions/
ml/                              Lane 2   existing training pipeline, unchanged
```

## Timeline

The demo date is unknown; this assumes early December. Slide it to fit.

| Week | Dates | Goal | Done when |
|---|---|---|---|
| 1 | Oct 19–25 | Setup + contracts frozen | Repo skeleton builds, mocks exist, parts ordered, all 4 sign off on contracts |
| 2–3 | Oct 26–Nov 8 | Each lane builds alone against mocks | Each lane's week 2–3 checklist below is done |
| 4 | Nov 9–15 | **Integration 1:** real sound → glasses → phone → watch arrow | Clap behind you, the watch shows an arrow pointing behind |
| 5 | Nov 16–22 | Firebase live, filters, history, first field test | Full app runs for 30 min in a real room |
| 6 | Nov 23–29 | Buffer (Thanksgiving) | n/a |
| 7 | Nov 30–Dec 6 | Polish, printed frame, demo rehearsal | Demo runs three times in a row without a restart |

---

## Lane 1: Glasses & Input

**Owns:** the physical glasses, the firmware, and the iPhone code that receives BLE and turns it
into `SoundFrame`s. Done when Lane 2 can swap `WavFileFrameSource` for the real thing.

**Stack:** Seeed XIAO ESP32-S3 (the non-Sense version is fine now that there's no camera),
4× INMP441 I2S mics, LiPo, C++ on PlatformIO (Arduino-ESP32), `esp-dsp` for FFT, NimBLE for BLE.
iPhone side: CoreBluetooth.

- [ ] **W1** Order parts: `docs/hardware-bom.md` minus the camera and LEDs.
- [ ] **W1** Breadboard the 4 mics on both I2S ports with shared BCLK/WS (see BOM note 1, the hard part).
- [ ] **W1** Stream raw 4-channel audio to a laptop over Wi-Fi UDP (plan already in `docs/networking.md`) and save `.wav` files. These recordings are also Lane 2's test data.
- [ ] **W1** Finalise the BLE packet with Lane 2.
- [ ] **W2** Port `gcc_phat` from `pi/sound_ring.py` to the ESP32 with `esp-dsp`. Compare against the Python version on the same recordings: target within ±15°.
- [ ] **W2** Per-frame level (dBFS), onset flag, IMA ADPCM encoder.
- [ ] **W3** BLE peripheral sending the packet at 50 Hz.
- [ ] **W3** `Input` module: CoreBluetooth scan/connect/reconnect, decode, `AsyncStream<SoundFrame>`, `bluetooth-central` background mode.
- [ ] **W3** Test: phone locked in a pocket for 10 min, gaps logged, under 1% packets lost.
- [ ] **W4+** Frame CAD and 3D print (use `docs/rendering/` as the reference), wiring into the temples, battery-life measurement, loudness calibration with Lane 2.
- [ ] **W4+** Update `docs/networking.md` and `docs/hardware-bom.md` to the BLE, no-camera design.

**Notes:** CoreBluetooth does not work in the iOS Simulator, so you need a real iPhone. The
LightBlue app is useful for poking at the glasses before your Swift code exists.

## Lane 2: Detection (ML)

**Owns:** everything between `SoundFrame` and `SoundEvent`: classifier choice, thresholds,
tracking a sound from start to stop, retraining. Done when the `SoundEvent` stream is accurate
and fast on real-room audio.

**Stack:** Swift, Apple `SoundAnalysis` *or* TensorFlowLiteSwift with our existing
`pi/*.tflite` files, Python `ml/` for retraining.

- [ ] **W1** Bake-off on the ESC-50 test fold (fold 5), our 12 labels:
  - **A.** Apple's built-in classifier (`SNClassifySoundRequest`, 300+ classes, map them to our labels)
  - **B.** Our YAMNet + head via TensorFlowLiteSwift

  Compare accuracy, latency and false positives on background noise. Pick one and write the result in `ml/README.md`.
- [ ] **W2** `Detection` module: 1 s ring buffer, hop 0.1 s, per-class thresholds and persistence (port from `ml/config.py` and `demo/live_demo.py`), loudness gate, `SoundEvent` start/update/stop tracking, attach the latest azimuth.
- [ ] **W2** Unit tests driven by `WavFileFrameSource` on ESC-50 clips.
- [ ] **W3** ADPCM test: encode/decode the test set, measure the accuracy drop. If it's over ~2 points, tell Lane 1 now.
- [ ] **W3** Priority scoring (from `CLASS_PRIORITY`), `isUrgent` rule, label → `FilterCategory` mapping as a data file, not code.
- [ ] **W4+** Record our own clips through the real glasses (doorbell, dryer, smoke alarm, baby cry), retrain the head in `ml/`, ship it through Firebase ML model hosting with Lane 3.
- [ ] **W4+** Loudness calibration with Lane 1 (phone SPL meter app as the reference).

**Targets:** median label latency ≤ 0.4 s from onset, false positives measured on 30 min of real
room noise, safety classes (siren, alarm, glass, horn) missed under 5%.

## Lane 3: Cloud & Links

**Owns:** Firebase, getting events to the watch, notifications, and storing data for
retraining. Done when settings sync, history shows up, and an urgent sound buzzes the wrist with
the phone locked.

**Stack:** Firebase (Auth, Firestore, Cloud Storage, ML model downloader, Cloud Functions, FCM,
Crashlytics) via Swift Package Manager, WatchConnectivity, UserNotifications.

- [ ] **W1** Create the Firebase project, add the iOS app, Sign in with Apple, local Emulator Suite.
- [ ] **W1** Decide with the team: paid Apple Developer account ($99/yr). Free accounts can install on devices, but push notifications (FCM) and TestFlight need paid.
- [ ] **W1** Firestore schema + security rules (each user reads and writes only their own data):
  ```
  users/{uid}                 displayName, filters: [category], buzzLabels: [label],
                              sensitivity, createdAt
  users/{uid}/events/{id}     label, confidence, azimuthDeg, levelDb,
                              startedAt, endedAt, deviceId
  users/{uid}/devices/{id}    name, firmwareVersion, lastBattery, lastSeen
  ```
- [ ] **W2** `Cloud` module: settings read/write, offline persistence, event history upload batched (every 30 s and on app background, never per frame). Build against `MockEventSource`.
- [ ] **W3** WatchConnectivity bridge:
  - phone → watch: active events via `sendMessage` when reachable, `updateApplicationContext` as the latest-state fallback
  - watch → phone: settings changes
- [ ] **W3** Urgent alerts: local notification with `.timeSensitive` interruption level. With the phone locked, iOS mirrors it to the watch with a haptic, so it works even when the watch app is closed.
- [ ] **W4** "That was wrong" flow: upload the last 2 s of audio + the correct label to Cloud Storage (opt-in) as Lane 2's retraining data. Model hosting with Lane 2.
- [ ] **W5 (optional)** Cloud Function: push a safety event to a caregiver's phone via FCM.
- [ ] **Stretch** Cloud Run "second opinion" classifier: the phone uploads a clip after each event, a bigger model relabels it for history. Only if the team wants cloud inference in the demo. Never on the live path.

**Notes:** a phone notification only mirrors to the watch when the iPhone is locked. When the
phone is unlocked, the phone shows it instead. Test both.

## Lane 4: Apps (UI)

**Owns:** every screen on the iPhone and watch, the Xcode project, and the haptic design. Done
when the apps are complete on mocks and swapping in the real source is a one-line change.

**Stack:** SwiftUI (iOS + watchOS), Swift Charts for history, WatchKit haptics,
`WKExtendedRuntimeSession` to keep the watch view alive.

- [ ] **W1** Sketch both apps (paper or Figma), review with the team.
- [ ] **W1** Create the Xcode project + `SoundRingKit` package skeleton + `MockEventSource`. Push before Wednesday so everyone can start.
- [ ] **W2** **Watch bird's-eye view:** wearer icon in the centre (top = facing direction), an arrow or arc per active sound at its azimuth, label + SF Symbol, size/opacity by loudness, fades out after the sound stops. Haptic pattern per category.
- [ ] **W3** **iPhone screens:**
  - Live: same radar, bigger, plus a list of active sounds
  - Filters: Safety / Privacy / Babies toggles + per-sound overrides
  - Settings: sensitivity, which sounds buzz the wrist
  - Device: connection state, battery
- [ ] **W4** History (Firestore via Lane 3, Swift Charts), onboarding, glasses pairing, sign-in.
- [ ] **W5+** Accessibility: VoiceOver labels, Dynamic Type, colours that work for colour-blind users, never colour alone. Our users are deaf or hard of hearing, so every cue must be visual or haptic, never a sound.
- [ ] **W5+** Usability test with at least two real users. Feed the results into the open decisions below.

**Notes:** the watch and iPhone simulators both work with `MockEventSource`, so you need no
hardware until week 4.

---

## Team-wide

- **Hardware for the team:** everyone on Lanes 1–4 needs a Mac with current Xcode. At least one
  iPhone + paired Apple Watch for testing (BLE and haptics need real devices).
- **Git:** one branch per feature, PR into `main`, one reviewer from another lane. Contract
  changes (`Sources/Models/`) need all four.
- **Weekly sync (15 min):** each lane reports what's done against its checklist, plus anything
  blocking. Integration weeks get a joint working session.

## Open decisions

| # | Decision | Owner | By |
|---|---|---|---|
| 1 | Classifier: Apple built-in vs our YAMNet head | Lane 2 | End of W1 |
| 2 | Final BLE packet format | Lane 1 + 2 | End of W1 |
| 3 | Paid Apple Developer account | Team | End of W1 |
| 4 | How loudness is shown on the watch (size, opacity, rings, number) | Lane 4 + 2 | W3 |
| 5 | Which sounds go in each filter, and which are urgent | Team, from user interviews | W3 |
| 6 | Cloud inference stretch goal: yes or no | Team | W4 |
| 7 | Demo date | Team | Now |
