# SoundRingKit

The Swift package with the iPhone app's non-UI code. No third-party dependencies.
Platforms: iOS 17 and macOS 14, so the tests run on a Mac without a phone.

## Run the tests

```sh
cd ios/Packages/SoundRingKit
swift build
swift test
```

Needs Swift 6 (Xcode 16 or later). Tests use Swift Testing (`import Testing`). One test reads
`ml/models/labels.json` from the repo, so run it from a full checkout.

## Targets

| Target | Owner | What lives here |
|---|---|---|
| `Models` | all three | The contracts from `docs/team-plan.md`: `BoxPosition`, `BoxLevel`, `SoundFrame`, `BoxSource`, `SoundLabel`, `FilterCategory`, `SoundEvent`, `SoundEventSource`. Plus the BLE packet layouts (`LevelPacket`, `AudioPacket`, `ControlCommand`, `BLESequence`) and the angle helpers (`Azimuth`, `BoxPosition.facingDeg`). |
| `Input` | Lane 1 (B) | CoreBluetooth for the 4 boxes, ADPCM decode, `WavFileBoxSource`. Placeholder for now. |
| `Detection` | Lane 2 (Avery) | Preprocessing, direction, classifier, event tracking. Placeholder for now. |
| `Cloud` | Lane 3 (C) | Firebase, notifications, later WatchConnectivity. Placeholder for now. |
| `ModelsTests` | all three | Labels match `ml/models/labels.json`, packets round-trip (including seq wrap), angle helpers. |

`Input`, `Detection` and `Cloud` depend only on `Models`, never on each other. Lanes talk
through the `BoxSource` and `SoundEventSource` protocols.

## Rule for `Models`

`Sources/Models/` is the only coupling between lanes. **Any change to it needs approval from
all three software owners** (Avery, B and C) on the PR. That includes renaming a field, adding
an enum case or changing a byte offset. Change `docs/team-plan.md` in the same PR so the doc
and the code stay the same.

## Notes on the contracts

- `SoundLabel` raw values are the names in `labels.json` (`glass_break`, `car_horn`,
  `baby_cry`), so they match the model and the Python code. The model's `other` class has no
  case: `SoundLabel(rawValue: "other")` is nil, which is how Detection drops it.
- Packet parsing is pure (`Data` in, struct out), little-endian, and throws
  `BLEPacketError.wrongLength` on any other size. `encoded()` does the reverse, for the fake
  box and tests. ADPCM decoding is not in `Models`.
- Angles: 0° ahead, clockwise positive, 90° right, 180° behind, 270° left.
