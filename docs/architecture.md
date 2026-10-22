# Architecture: how a sound becomes an alert

One page so the whole team agrees on the layers, the tech stack and where data goes.
**Phone app first. Apple Watch later.** Hardware is the 4 body-worn boxes from
[`body-boxes-plan.md`](body-boxes-plan.md).

![Data flow](data-flow.png)

Edit the diagram: open [`data-flow.excalidraw`](data-flow.excalidraw) at
[excalidraw.com](https://excalidraw.com) (menu → Open), then export a PNG over `data-flow.png`.

## The one rule

**Audio never leaves the phone.** Everything except Firebase runs inside the iPhone app.

## Where does each part live?

**Preprocessing and inference are inside the iPhone app.** They're the same app you install
from Xcode, not a separate server.

The iPhone app has two halves:

```
┌─────────────── iPhone app ───────────────┐
│                                           │
│  BEHIND THE SCENES (code, no screens)     │
│   1. Input         catch Bluetooth audio  │
│   2. Preprocessing find direction,        │
│                    skip silence           │
│   3. Inference     YAMNet → "car horn"    │
│                                           │
│  WHAT YOU SEE (screens)                   │
│   4. Frontend      arrow + name + buzz    │
│                                           │
└───────────────────────────────────────────┘
        │ saves settings + history
        ▼
     Firebase (cloud)
```

People usually call "behind the scenes" the *backend* and picture a server. **Here the
behind-the-scenes code runs on the phone itself:** Swift files that run silently while the
screens are open.

| Part | Folder in the Xcode project |
|---|---|
| Input | **`ios/Packages/SoundRingKit/Sources/Input/`** |
| Preprocessing + Inference | **`ios/Packages/SoundRingKit/Sources/Detection/`** |
| Saving to Firebase | **`ios/Packages/SoundRingKit/Sources/Cloud/`** |
| Screens | **`ios/SoundRing/`** |

**One sound, start to finish:** horn honks → box hears it → Bluetooth → **phone: Input →
Preprocessing → Inference → Screen**. Firebase only gets a copy for history afterward.

## Why the phone, not the watch?

**The phone is the brain. The watch is just a screen on your wrist.** The watch pauses apps
when your wrist drops, has a small battery, and handles 4 Bluetooth boxes poorly. So the phone
does the work and sends the watch a tiny message like "horn, behind, loud." The phone app alone
is a complete product; the watch comes later.

## Do we train a model?

**No. The model is already trained.** YAMNet comes pretrained from Google, and our head is in
`ml/models/sound_head.tflite` (13 sounds, 93.8% on test data). The app just loads the
`.tflite` files. Retrain later only if accuracy is bad through the boxes' mics, or to add new
sounds.

## The layers

| # | Layer | Does | Tech | Goes to |
|---|---|---|---|---|
| 1 | Sound boxes (×4) | Hear sound, measure loudness | ESP32-C3 + mic, Arduino C++ | **The phone, over Bluetooth: loudness + audio** |
| 2 | Input | Catch the Bluetooth data, unzip the audio | Swift, CoreBluetooth | **Preprocessing: audio + loudness** |
| 3 | Preprocessing | Find direction, ignore silence, keep the last 1 s | Swift | **The model: 1 s of audio + the angle** |
| 4 | Model (inference) | YAMNet names the sound | TensorFlow Lite, our `.tflite` files | **The screen: "horn, behind you, loud"** |
| 5 | Screen (frontend) | Show the arrow + name, buzz if urgent | SwiftUI | **Firebase: settings + history** |
| 6 | Firebase (backend) | Remember settings and history | Auth + Firestore, free plan | **Back to the app when it opens** |
| – | Training (optional, later) | Retrain the model on a laptop | Python, `ml/` | **The model: new `.tflite` files** |
| – | Watch (later) | Arrow + buzz | SwiftUI on watchOS | – |

## Do we need a backend server?

**No. Firebase is the backend.** The app writes to it directly, and there's no server code to
write.

Running the model on a server would be slower, would stop working with no signal, would upload
people's conversations, and would need Firebase's paid plan.

## Build order

1. **Screen** on fake sounds (no hardware needed)
2. **Model** on a recorded `.wav` file
3. **Preprocessing**
4. **Firebase**
5. **Real boxes** over Bluetooth (needs a real iPhone)

Steps 1, 2 and 4 can be built at the same time by different people.
