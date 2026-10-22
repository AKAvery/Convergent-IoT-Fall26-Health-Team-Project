# Team plan: who builds what

Four tech members, four lanes. Each lane has one owner, a clear boundary, and a contract it
hands to the next lane. Everyone builds against **mocks** of the other lanes in weeks 2–3, so
nobody waits on anybody. Written 2026-10-19, updated 2026-10-22 for the body-worn boxes and
phone-first priority. The split is a suggestion: swap names freely, keep the boundaries.

**Priority: the iPhone app. The Apple Watch app comes later.**

```
 LANE 1: Boxes & Input          LANE 2: Detection              LANE 4: iPhone app (UI)
┌────────────────────────┐    ┌──────────────────────────┐    ┌──────────────────────────┐
│ 4 boxes: mic → ESP32   │    │ direction from loudness  │    │ live view: arrows,       │
│ loudness + audio       │───▶│ YAMNet + head → label    │───▶│ filters, settings,       │
│ BLE → iPhone receiver  │    │ track sounds over time   │    │ history, alerts          │
└────────────────────────┘    └──────────────────────────┘    └──────────────────────────┘
   BoxLevel + SoundFrame               SoundEvent                       ▲
                                           │                            │
                                           ▼                            │
                              ┌──────────────────────────┐              │
                              │ LANE 3: Cloud & Alerts   │──────────────┘
                              │ Firebase, notifications, │  settings, history
                              │ watch link (later)       │
                              └──────────────────────────┘
```

| Lane | Owner | One-line job | Hands off |
|---|---|---|---|
| 1. Boxes & Input | _name_ | Get loudness + audio from 4 boxes onto the iPhone | `BoxLevel` + `SoundFrame` streams |
| 2. Detection | _name_ | Turn that into "siren, 90° right, loud" | `SoundEvent` stream |
| 3. Cloud & Alerts | _name_ | Firebase (free tier), notifications, later the watch link | Settings, history |
| 4. iPhone app (UI) | _name_ | Everything the user sees and touches | The product |

All of Lanes 1 (phone side), 2, 3 and 4 is code **inside the same iPhone app**. See
`docs/architecture.md` for where each part lives.

## Architecture decisions (settled)

- **Everything runs on the iPhone; Firebase is the only backend.** Live alerts need to land
  within about 0.3 s and must keep working with no signal. A server round trip adds
  100–500 ms, uploads people's conversations, and would need a paid plan. Firebase handles
  settings and history only. No server to write.
- **4 body-worn boxes, direction from loudness.** The body blocks sound, so the box facing a
  sound hears it loudest. No clock sync, no fixed mic spacing, no user calibration. Details in
  `docs/body-boxes-plan.md`.
- **Each box connects straight to the iPhone over BLE.** iOS keeps BLE accessories running in
  the background (`bluetooth-central`), so alerts keep coming with the phone locked in a pocket.
  Every box sends a loudness number 10×/s; only the loudest box streams audio (~64 kbit/s).
- **Inference on the loudest box only.** All boxes hear the same sound; the loudest has the
  cleanest copy.
- **Classifier: YAMNet + our trained head** (`ml/models/`, 13 classes, 93.8%), via
  TensorFlowLiteSwift. Already trained; no training needed to ship.
- **The phone is the brain; the watch is a screen.** The watch app comes later and only shows
  what the phone sends it.
- **Swift everywhere on Apple.** SwiftUI, one Xcode project, shared Swift package for the
  contracts below.
- **$0 budget for software and services.** This is a demo. See [Free-tier limits](#free-tier-limits)
  for what that rules out and the workaround for each.

## Free-tier limits

**Apple: free Personal Team, no paid Developer Program.** Every teammate signs in to Xcode
with their own Apple ID and installs to their own devices over the cable.

| Can't do on free | Workaround |
|---|---|
| Push notifications (APNs, so also FCM) | **Local** notifications from the iPhone app. These work on free accounts and (later) mirror to the watch with a haptic when the phone is locked. |
| Sign in with Apple | Firebase **Anonymous Auth** (one tap, no UI). Email/password if we need named accounts. |
| TestFlight / App Store | Install from Xcode. Apps **expire after 7 days**: re-install the night before the demo. |
| Shared bundle IDs across Apple IDs | Each person builds with their own bundle ID suffix, e.g. `com.convergent.soundring.<name>`, set in a local, git-ignored `.xcconfig`. |

**The 7-day expiry is less work than it sounds.** Every Run from Xcode with the device plugged
in restarts the 7 days, so during development it never comes up. Only the demo device needs a
re-install the night before. Switching frameworks doesn't help: the expiry comes from Apple's
code signing, so React Native, Flutter and Expo apps expire the same way. Expo Go has no BLE,
and Safari on iPhone has no Bluetooth (so no web app). If plugging in gets old, SideStore
(free) re-signs the app with your own Apple ID over Wi-Fi in the background. Also ask
Convergent or a UT professor whether UT is in Apple's free University Program; check whether
its installs last longer than 7 days.

Background BLE (`bluetooth-central`), haptics, local notifications and (later)
WatchConnectivity all work on a free account. If Xcode refuses the Time Sensitive Notifications
capability on a Personal Team, drop it and use a plain local notification.

**Firebase: Spark plan only, never upgrade to Blaze.** Blaze needs a credit card even when
usage stays inside the free quotas.

| Free on Spark (use) | Needs Blaze (don't use) | Instead |
|---|---|---|
| Authentication | Cloud Storage (Blaze-only since Feb 2026) | Save clips on the phone, AirDrop them to a laptop into `ml/data/my_clips/` |
| Cloud Firestore (1 GiB, 50k reads / 20k writes per day) | Cloud Functions | Nothing server-side. The app writes to Firestore directly; rules enforce access. |
| Crashlytics, Analytics | Cloud Run (cloud inference) | Not doing it |
| Emulator Suite (local testing) | ML model hosting (not needed for a demo) | Bundle the `.tflite` model in the app; rebuild to update |

Firestore quotas are plenty: batched history writes at a few hundred per day per tester.

**Hardware is the only real cost**, about $75 for 4 boxes (`docs/hardware-bom.md`). Ask
Convergent for budget or borrow parts before buying.

## The contracts (agree in week 1, then freeze)

These are the only coupling between lanes. Change them only by a PR that all four people
approve.

### 1. BLE: each box → iPhone (draft v0)

Each box advertises as `SoundBox-FRONT`, `SoundBox-BACK`, `SoundBox-LEFT` or `SoundBox-RIGHT`
(set by one constant in the firmware) and has one service with three characteristics:

| Characteristic | Direction | When | Content |
|---|---|---|---|
| `level` | box → phone, notify | 10 Hz, always | 5 bytes, below |
| `audio` | box → phone, notify | 50 Hz, **only after `control` = 1** | 169 bytes, below |
| `control` | phone → box, write | when the loudest box changes | 1 byte: 1 = start audio, 0 = stop |

```
level (5 bytes)
offset  size  field
0       2     seq          uint16, wraps; receiver logs gaps
2       2     peak_db      int16, dBFS × 10, peak of the last 100 ms
4       1     flags        bit0 = clipped, bit1 = low battery

audio (169 bytes, fits a 185-byte iOS MTU)
offset  size  field
0       2     seq          uint16, wraps
2       2     reserved     0
4       1     flags        bit0 = clipped
5       4     adpcm_state  int16 predictor + uint8 step index + uint8 pad (IMA ADPCM)
9       160   audio        320 samples, 16 kHz mono, IMA ADPCM 4-bit
```

**Firmware rules:** auto-gain off, the same fixed gain on all 4 boxes.

**Angle convention (everyone uses this):** 0° = straight ahead, clockwise positive,
90° = right, 180° = behind, 270° = left.

### 2. `BoxLevel` + `SoundFrame`: Lane 1 → Lane 2

```swift
enum BoxPosition: String, Codable, CaseIterable { case front, back, left, right }

struct BoxLevel: Sendable {
    let box: BoxPosition
    let seq: UInt16
    let receivedAt: Date
    let peakDbfs: Float
    let clipped: Bool
}

struct SoundFrame: Sendable {
    let box: BoxPosition     // which box this audio came from
    let seq: UInt16
    let receivedAt: Date
    let samples: [Int16]     // 320 samples, 16 kHz mono, already ADPCM-decoded
}

protocol BoxSource {
    var levels: AsyncStream<BoxLevel> { get }
    var frames: AsyncStream<SoundFrame> { get }
    func streamAudio(from box: BoxPosition)   // Lane 2 calls this when the loudest box changes
}
```

Mock: `WavFileBoxSource` plays a `.wav` as `SoundFrame`s and makes up 4 `BoxLevel` streams for
a sound that slowly circles the wearer. Lane 2 uses it until real boxes exist.

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
    var azimuthDeg: Float?    // same convention as above; nil if direction is unclear
    var levelDb: Float        // dB above the loudest box's quiet level
    let startedAt: Date
    var updatedAt: Date
    var isActive: Bool        // false once the sound has stopped
    var isUrgent: Bool        // alert + buzz even if the app is in the background
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
firmware/                        Lane 1   PlatformIO project, one code base for all 4 boxes
ios/SoundRing.xcodeproj          Lane 4   target: SoundRing (iOS); SoundRingWatch added later
ios/Packages/SoundRingKit/
    Sources/Models/              ALL      the contracts above; PR needs 4 approvals
    Sources/Input/               Lane 1   CoreBluetooth for 4 boxes, ADPCM decode, WavFileBoxSource
    Sources/Detection/           Lane 2   preprocessing, direction, classifier, event tracking
    Sources/Cloud/               Lane 3   Firebase, notifications, (later) WatchConnectivity
ios/SoundRing/                   Lane 4   SwiftUI screens
firebase/                        Lane 3   firestore.rules, firebase.json (emulators)
ml/                              Lane 2   trained model + training pipeline, unchanged
```

## Timeline

The demo date is unknown; this assumes early December. Slide it to fit.

| Week | Dates | Goal | Done when |
|---|---|---|---|
| 1 | Oct 19–25 | Setup + contracts frozen | Repo skeleton builds, mocks exist, parts ordered, all 4 sign off on contracts |
| 2–3 | Oct 26–Nov 8 | Each lane builds alone against mocks | Each lane's week 2–3 checklist below is done |
| 4 | Nov 9–15 | **Integration 1:** real sound → boxes → phone arrow | Clap behind you, the phone shows an arrow pointing behind |
| 5 | Nov 16–22 | Firebase live, filters, history, first field test | Full app runs for 30 min in a real room |
| 6 | Nov 23–29 | Buffer (Thanksgiving) | n/a |
| 7 | Nov 30–Dec 6 | Polish, cases, demo rehearsal | Demo runs three times in a row without a restart |

The watch app starts only after week 5 is done, if there's time.

---

## Lane 1: Boxes & Input

**Owns:** the 4 boxes, the firmware, and the iPhone code that receives BLE and turns it into
`BoxLevel`s and `SoundFrame`s. Done when Lane 2 can swap `WavFileBoxSource` for the real thing.

**Stack:** Seeed XIAO ESP32-C3, 1× INMP441 I2S mic per box, LiPo, C++ on PlatformIO
(Arduino-ESP32), NimBLE. iPhone side: CoreBluetooth.

- [ ] **W1** Order parts: `docs/hardware-bom.md`.
- [ ] **W1** Breadboard one box. Print the peak level (dBFS) every 100 ms to the serial monitor. Auto-gain off.
- [ ] **W1** **Body-shadow test** with 2 boxes (chest + back): clap in front, then behind. Pass = the facing box reads ≥ 6 dB louder every time. Report the result to the team.
- [ ] **W1** Finalise the BLE contract with Lane 2.
- [ ] **W2** Firmware: `level` characteristic at 10 Hz, clip flag, IMA ADPCM encoder, `audio` characteristic started and stopped by `control`.
- [ ] **W2** Record `.wav` files from a box for Lane 2's tests.
- [ ] **W3** `Input` module: scan for and connect to all 4 boxes, reconnect on drop, decode, `BoxSource` streams, `bluetooth-central` background mode.
- [ ] **W3** Test: phone locked in a pocket for 10 min, gaps logged, under 1% packets lost on every box.
- [ ] **W4+** Copy to 4 boxes, cases with clips, battery-life measurement, matching gain on all 4.

**Notes:** CoreBluetooth does not work in the iOS Simulator, so you need a real iPhone. The
LightBlue app is useful for poking at a box before your Swift code exists.

## Lane 2: Detection

**Owns:** everything between `BoxSource` and `SoundEvent`: preprocessing, direction, choosing
the loudest box, the classifier, thresholds, tracking a sound from start to stop. Done when the
`SoundEvent` stream is accurate and fast on real-room audio.

**Stack:** Swift, Accelerate, TensorFlowLiteSwift with the `.tflite` files in `ml/models/`.

- [ ] **W1** Load YAMNet + our head in a Swift test target. Run it on ESC-50 clips and check the labels match the Python version in `demo/live_demo.py`.
- [ ] **W2** Inference: 1 s ring buffer, hop 0.1 s, per-class thresholds and persistence (port from `ml/config.py` and `demo/live_demo.py`), loudness gate, `SoundEvent` start/update/stop tracking.
- [ ] **W2** Unit tests driven by `WavFileBoxSource`.
- [ ] **W3** Direction (`docs/body-boxes-plan.md`): rolling quiet level per box (quietest in the last 10 s), peak hold over 0.3 s, `atan2(RIGHT − LEFT, FRONT − BACK)`, fall back to the loudest box when the result is tiny.
- [ ] **W3** Loudest-box switching: call `streamAudio(from:)` when another box is louder by 3 dB for 0.3 s.
- [ ] **W3** ADPCM test: encode/decode the test set, measure the accuracy drop. If it's over ~2 points, tell Lane 1 now.
- [ ] **W3** Priority scoring (from `CLASS_PRIORITY`), `isUrgent` rule, label → `FilterCategory` mapping as a data file, not code.
- [ ] **W4+** Direction accuracy on real boxes: 8 positions around the wearer, record hits.
- [ ] **Optional** If accuracy through the boxes' mics is bad, record our own clips and retrain the head in `ml/`.

**Targets:** median label latency ≤ 0.4 s from onset, false positives measured on 30 min of real
room noise, safety classes (siren, alarm, glass, horn) missed under 5%, direction right to
within one side (front / back / left / right) 9 times out of 10.

## Lane 3: Cloud & Alerts

**Owns:** Firebase, notifications, saving clips for retraining, and later the watch link. Done
when settings sync, history shows up, and an urgent sound alerts with the phone locked.
Everything stays on free tiers (see [Free-tier limits](#free-tier-limits)).

**Stack:** Firebase on the Spark plan (Anonymous Auth, Firestore, Crashlytics) via Swift Package
Manager, UserNotifications (local only). Later: WatchConnectivity.

- [ ] **W1** Create the Firebase project on Spark (don't add billing), add the iOS app, Anonymous Auth, local Emulator Suite.
- [ ] **W1** Set up the per-person bundle ID `.xcconfig` with Lane 4 so everyone can build on a free Apple ID.
- [ ] **W1** Firestore schema + security rules (each user reads and writes only their own data):
  ```
  users/{uid}                 displayName, filters: [category], buzzLabels: [label],
                              sensitivity, createdAt
  users/{uid}/events/{id}     label, confidence, azimuthDeg, levelDb,
                              startedAt, endedAt
  users/{uid}/boxes/{id}      position, firmwareVersion, lastBattery, lastSeen
  ```
- [ ] **W2** `Cloud` module: settings read/write, offline persistence, event history upload batched (every 30 s and on app background, never per frame). Build against `MockEventSource`.
- [ ] **W3** Urgent alerts: local notification with `.timeSensitive` interruption level, so it shows and vibrates with the phone locked.
- [ ] **W4** "That was wrong" flow: save the last 2 s of audio as a `.wav` named with the correct label on the phone, and export through the share sheet (AirDrop to a laptop, into `ml/data/my_clips/<label>/`).
- [ ] **Later** Watch link: phone → watch active events via `sendMessage` when reachable, `updateApplicationContext` as the latest-state fallback; watch → phone settings changes.
- [ ] **Later (optional)** Caregiver view: a second phone signed in to the same account reads the `events` collection live with a Firestore listener.

## Lane 4: iPhone app (UI)

**Owns:** every screen, the Xcode project, and the haptic design. Done when the app is complete
on mocks and swapping in the real source is a one-line change.

**Stack:** SwiftUI, Swift Charts for history, haptics. Later: SwiftUI on watchOS.

- [ ] **W1** Sketch the app (paper or Figma), review with the team.
- [ ] **W1** Create the Xcode project + `SoundRingKit` package skeleton + `MockEventSource`. Push before Wednesday so everyone can start.
- [ ] **W2** **Live view:** bird's-eye view with the wearer in the centre (top = facing direction), an arrow per active sound at its angle, label + SF Symbol, size/opacity by loudness, fades out after the sound stops. List of active sounds below. Haptic pattern per category.
- [ ] **W3** **Screens:**
  - Filters: Safety / Privacy / Babies toggles + per-sound overrides
  - Settings: sensitivity, which sounds alert
  - Boxes: 4 dots (FRONT / BACK / LEFT / RIGHT) showing connected + battery
- [ ] **W4** History (Firestore via Lane 3, Swift Charts), onboarding (how to wear the boxes), sign-in.
- [ ] **W5+** Accessibility: VoiceOver labels, Dynamic Type, colours that work for colour-blind users, never colour alone. Our users are deaf or hard of hearing, so every cue must be visual or haptic, never a sound.
- [ ] **W5+** Usability test with at least two real users. Feed the results into the open decisions below.
- [ ] **Later** Watch app: the same bird's-eye view on the wrist, arrows + buzz, fed by the phone.

**Notes:** the iPhone Simulator works with `MockEventSource`, so you need no hardware until
week 4.

---

## Team-wide

- **Hardware for the team:** everyone on Lanes 1–4 needs a Mac with current Xcode and a free
  Apple ID. At least one real iPhone for BLE testing. The demo phone must be the Apple ID
  owner's device, installed from their Mac.
- **Git:** one branch per feature, PR into `main`, one reviewer from another lane. Contract
  changes (`Sources/Models/`) need all four.
- **Weekly sync (15 min):** each lane reports what's done against its checklist, plus anything
  blocking. Integration weeks get a joint working session.

## Open decisions

| # | Decision | Owner | By |
|---|---|---|---|
| 1 | Final BLE contract | Lane 1 + 2 | End of W1 |
| 2 | Hardware money: Convergent budget or borrowed parts | Team | End of W1 |
| 3 | How loudness is shown in the app (size, opacity, rings, number) | Lane 4 + 2 | W3 |
| 4 | Which sounds go in each filter, and which are urgent | Team, from user interviews | W3 |
| 5 | Whose iPhone is the demo device | Team | W4 |
| 6 | Demo date | Team | Now |

Decided: classifier = YAMNet + our trained head (2026-10-22).
