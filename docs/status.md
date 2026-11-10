# Build status: what's done, what's not

Last checked against the code: 2026-11-09

**This file is the ground truth for what is built.** Plan from it. When something gets done,
tick it here in the same PR and add a line to the [Change log](#change-log).

**How it reads:** a sound goes through the stages in order, 1 to 8. Each stage says how it works
in plain words, then lists its checklist.

- `[x]` = done and checked in the code
- `[ ]` = not done yet
- **Partial:** = started but not finished
- **Decide:** = a choice the team still has to make

| Stage | What | State |
|---|---|---|
| [1](#1-sound-boxes-hardware) | Sound boxes (hardware) | ✅ mostly done |
| [2](#2-bluetooth-to-the-phone) | Bluetooth to the phone | ✅ done |
| [3](#3-finding-direction-where-is-it) | Finding direction | ✅ done |
| [4](#4-naming-the-sound-what-is-it) | Naming the sound | ✅ done |
| [5](#5-name-alerts-bonus) | Name alerts | ✅ done |
| [6](#6-iphone-screens) | iPhone screens | 🟡 partly real |
| [7](#7-firebase-saving-settings-and-history) | Firebase | ❌ not started |
| [8](#8-apple-watch) | Apple Watch | 🟡 screens only |

Jump to: [Gaps, in order](#gaps-in-order) · [Change log](#change-log)

## 1. Sound boxes (hardware)

Each box is a tiny ESP32 computer with 1 mic, worn on the chest, back, left or right. The mic
listens 16,000 times a second. Every 0.1 s the box sends the phone one number: how loud things
were just now. Deep rumble is filtered out first so bumps don't count. When the phone says "send
me audio," that box also sends the actual sound, squeezed about 4× smaller (ADPCM) so it fits
over Bluetooth.

Code: [`firmware/`](../firmware/)

- [x] Mic reading at 16,000 samples a second
- [x] Loudness sent 10 times a second, rumble filtered out
- [x] Audio sent squeezed (ADPCM) when the phone asks
- [x] Fix for the mic's bias (DC offset)
- [x] Fix for loud sounds popping (limiter)
- [ ] Battery-level reading (needs a missing wire: a voltage divider)
- [ ] Clip-on cases
- [ ] Battery-life test

## 2. Bluetooth to the phone

The phone finds all the boxes, connects, and reads their loudness numbers plus the audio. It
"unzips" the squeezed audio back into normal sound. It keeps running when the app is in the
background.

Code: [`ios/Packages/SoundRingKit/Sources/Input/`](../ios/Packages/SoundRingKit/Sources/Input/)

- [x] Phone finds and connects to the boxes
- [x] Reads loudness and audio
- [x] Unzips audio; matches the Python version byte for byte
- [x] Keeps running in the background
- [x] Live test with 2 boxes (chest and back)
- [ ] Live test with all 4 boxes

## 3. Finding direction ("where is it?")

Your body blocks sound, so the box facing the sound hears it loudest. Each box learns its own
"quiet level" over the last 10 seconds. What counts is how far above quiet it is right now. Then
it's a tug of war: front vs back and left vs right give an angle (0° = in front, 180° = behind).

Only the loudest box sends audio. The phone only switches boxes when another one is clearly
louder for a while, so the arrow doesn't flicker.

Code: [`ios/Packages/SoundRingKit/Sources/Detection/Direction.swift`](../ios/Packages/SoundRingKit/Sources/Detection/Direction.swift)

- [x] Quiet level per box
- [x] Angle from the tug of war
- [x] Only the loudest box streams audio
- [x] Steady switching between boxes (no flicker)

## 4. Naming the sound ("what is it?")

The audio from the loudest box goes into YAMNet (Google's pretrained sound AI). YAMNet turns
1 s of sound into a fingerprint, and our small trained add-on reads that fingerprint and picks
from our 13 sounds: siren, alarm, glass break, car horn, baby cry, knock, clap, dog, cat,
appliance, speech, footsteps, and "other." Silence gets skipped, which saves battery. An event
tracker turns a stream of guesses into steady events like "siren started, still going, stopped."

Code: [`ios/Packages/SoundRingKit/Sources/Detection/`](../ios/Packages/SoundRingKit/Sources/Detection/),
model files in [`ml/models/`](../ml/models/)

- [x] YAMNet + our add-on running in the app
- [x] Silence skipped
- [x] Event tracker (start, ongoing, stop)
- [x] Checked against the Python version on 30 test clips

Adding a new sound means retraining the add-on (about 1 minute on a laptop). See
[`ml/README.md`](../ml/README.md). Moving a sound between filters, or marking it urgent, is a
Swift-only change.

## 5. Name alerts (bonus)

On-device speech-to-text listens for your name and says which direction it came from.

Code: [`ios/Packages/SoundRingKit/Sources/Names/`](../ios/Packages/SoundRingKit/Sources/Names/)

- [x] Hears the wearer's name
- [x] Shows which direction it came from

## 6. iPhone screens

The Live screen runs on the real pipeline. Some other screens still show fake demo data.

Code: [`ios/SoundRing/`](../ios/SoundRing/)

- [x] Live screen: arrow, sound name and loudness from the real pipeline
- [x] Filters on the Live screen
- [x] Setup/onboarding, Settings and Pins screens, built from the Figma designs
- [ ] Home stats ("X sounds today", "last session") on real data. **Partial:** screen built, fake demo data
- [ ] Box battery cards on real data. **Partial:** screen built, fake demo data
- [ ] Phone buzz (haptics) for urgent sounds
- [ ] Notifications for urgent sounds
- [ ] **Decide:** which sounds go in each filter
- [ ] **Decide:** which sounds count as urgent

## 7. Firebase (saving settings and history)

Not started. [`Cloud.swift`](../ios/Packages/SoundRingKit/Sources/Cloud/Cloud.swift) is an
empty placeholder. Settings are saved only on the phone, and there's no sound history.

- [ ] Login (Anonymous Auth)
- [ ] Settings sync
- [ ] Sound history

## 8. Apple Watch

Two watch pages are built: the main sound right now, and a list, with wrist taps. They play fake
demo scenes because the phone doesn't send the watch anything yet.

Code: [`ios/SoundRingWatch/`](../ios/SoundRingWatch/)

- [x] Main sound page
- [x] List page
- [x] Wrist taps
- [ ] Phone → Watch link (WatchConnectivity), replacing the demo scenes

## Gaps, in order

1. Phone buzz and notifications for urgent sounds (stage 6)
2. Firebase: login, settings sync, history (stage 7)
3. Home stats on real data (stage 6)
4. Phone → Watch link (stage 8)
5. Battery reading on the boxes, cases, battery-life test (stage 1)
6. A full 4-box live test (stage 2)
7. Decide the filter and urgent sound lists (stage 6)

## Change log

Newest first. One line per change.

| Date | Change |
|---|---|
| 2026-11-09 | First version, checked against the code on `main` (cd25ada) |
