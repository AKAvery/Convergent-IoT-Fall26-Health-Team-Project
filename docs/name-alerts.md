# Name alerts: "someone said your name"

Built and measured 2026-11-05. When someone says the wearer's name, the app shows a red **Your
name** alert with what was said ("Excuse me, Avery") and the direction it came from.

## How it works

1. The box audio the detector already gets (16 kHz, 16-bit) is also handed to Apple's on-device
   speech-to-text: `SpeechAnalyzer` + `SpeechTranscriber` (iOS 26 / macOS 26). This is the same
   format Apple's model asks for, so nothing is converted. Audio never leaves the phone.
2. Every transcript, in-progress ones included, is checked for the names in
   **Settings → Name alerts** (name plus nicknames, comma-separated). Whole words only, so
   "Avery" never fires on "every", "very", "bravery" or "ivory".
3. Each spoken call raises one alert, with the direction of the current sound.

Code: `ios/Packages/SoundRingKit/Sources/Names/` (`NameMatcher`, `NameListener`), wired in
`ios/SoundRing/Main/LiveSession.swift`, Settings card in `NameAlertsCard.swift`. Tests:
`swift test --filter NamesTests` (the speech tests run on macOS 26 with the real model).

Apple has its own **Name Recognition** (iOS 26, Settings → Accessibility). It listens through the
phone's mic and can't say where the voice came from. Ours hears through the pins and gives the
direction.

## What we measured

Test set: 28 phrases (12 with the name, 16 without, including sound-alikes), each spoken by 8 of
16 Mac voices, at 4 levels with the box's real room noise underneath (same noise and box chain
as `docs/noise-and-amplification.md`), so 896 clips. Then streamed through the app's own
`NameListener`:

| Clip level | "Avery" caught | "Kai" caught | False alarms |
|---|---|---|---|
| Clean | 42 / 64 (66%) | 13 / 32 | 0 |
| −20 dBFS (close, normal voice) | 39 / 64 (61%) | 12 / 32 | 0 |
| −30 dBFS | 30 / 64 (47%) | 4 / 32 | 0 |
| −40 dBFS (far) | 9 / 64 (14%) | 1 / 32 | 0 |

0 false alarms on the 512 clips without the name (sound-alikes like "every day", "It takes
bravery", "Hi guys", "kayak"), and never two alerts for one call.

**Delay** (measured in the app, from the moment the name is spoken): **1.7–2.5 s** in a room
with background noise. Where it goes: in noise Apple's model never hears a pause, so on its own it
only reports every ~3.9 s (2.8–3.8 s delays). The app now tells it to commit what it heard as
soon as our detector's `speech` stops (`NameListener.speechEnded()`), and the alert follows
~0.1 s later. What's left is the rest of the sentence plus ~0.8 s for the detector to notice the
talking stopped. Committing on a timer instead cut words in half ("Avery" became "."), and Apple's
own voice detector (`SpeechDetector`) made it slower (3.3–6 s), so neither is used. In a quiet
room Apple notices the pause itself (~1 s after the sentence).

**Live test (2026-11-05, real box over Bluetooth, real conversation):** transcripts were accurate
("Each battery is $9.", "$84 for one module."), and "Hello, Avery?" raised the alert. That run
also showed one call alerting twice when Apple split it across two segments; fixed (names already
alerted carry over to the next segment) and re-checked on the 896 clips: still 0 doubles.

**Mode choice:**

| Apple mode | "Avery" caught, clean / −20 / −30 / −40 | False alarms |
|---|---|---|
| **SpeechTranscriber** (used) | **42 / 39 / 30 / 9** | **0** |
| + the name as a hint (`contextualStrings`) | identical: the hint does nothing | 0 |
| DictationTranscriber (older model) | 37 / 37 / 23 / 0 | 0 |
| DictationTranscriber + name hint | 40 / 38 / 24 / 4 | 6 ("bravery", "ivory") |

## Limits

- **Misses are mostly mishearings**: "a worry", "Marie" or "Haveri" for Avery, and "Hi" for Kai.
  Several of the Mac voices are old robotic ones (one voice scored 0 / 6, two scored 6 / 6), so
  real voices should do better. **Next step: record real people calling a name through a box.**
- **Short names that sound like common words** (Kai → "Hi", "guy") are hard. Adding the common
  word as a nickname would fire all day, so don't.
- **Learning sound-alikes from the wearer's voice doesn't help.** We simulated a "say your name 3
  times" setup step: catches stayed the same (0.66 → 0.66) and false alarms crept up, because each
  speaker gets misheard differently. Not built.
- **Noise:** like the sound classes, quiet or far voices in room noise are mostly missed.
- **Needs iOS 26** (the app still runs on 17; the card says so). It **doesn't work in the iOS
  Simulator** (Apple's speech model isn't there). Use a real iPhone or "My Mac (Designed for
  iPad)".

## Debugging

Console.app, subsystem `edu.utexas.convergent.soundring`, category `names`: status, every alert,
and how long after the name it came. To also log what was said (off by default: it writes what
people around the wearer say into the system log), set `logTranscripts` to true.

## Demo without pins

The app can replay a recording through the whole box pipeline instead of Bluetooth: put a
16 kHz mono 16-bit WAV in the app's Documents folder and set `demoRecording` to its file name
(`SettingKey.demoRecording`). The Simulator always uses the bundled `demo_sounds.wav`.
