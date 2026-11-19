# Multiple sounds at once (all-boxes mode)

**Problem:** the original design listens to the loudest box only and draws one arrow. If a siren
is on your left and a baby is crying behind you, the phone hears one mixed signal and points
somewhere in between, at neither.

**Fix:** let all 4 boxes listen, and give each sound its own arrow.

## How it works, simply

Think of 4 friends standing around you, each with their own pair of ears.

1. **All 4 boxes send their audio** to the phone (not just the loudest one).
2. **The phone runs the sound model once per box.** Each box gets its own "what do I hear?"
   answer. The LEFT box might say "siren", the BACK box "baby cry".
3. **The phone merges the answers into one list of sounds.** If 3 boxes all say "siren", that is
   still one siren, not three.
4. **Each sound gets its own arrow.** For the siren, the phone listens more to the boxes that
   clearly heard a siren and less to boxes that were busy hearing something else. So the siren
   arrow points left and the baby arrow points behind.

```
LEFT box  ─audio─▶ model ─▶ "siren 90%, baby 10%" ─┐
BACK box  ─audio─▶ model ─▶ "siren 10%, baby 90%" ─┤  merge  ─▶ siren ← (left)
FRONT box ─audio─▶ model ─▶ "faint"               ─┤         ─▶ baby  ↓ (behind)
RIGHT box ─audio─▶ model ─▶ "faint"               ─┘
```

## The direction rule

Same "tug of war" as before (`atan2(RIGHT − LEFT, FRONT − BACK)`), with one change: each box's
pull is its loudness **times how sure that box is about this specific sound** (compared with the
box that is most sure).

- Siren: LEFT is sure (pulls with full strength), BACK barely thinks it's a siren (almost no
  pull). The arrow points left.
- Baby: the reverse. The arrow points behind.
- One sound that every box hears equally well: all boxes are equally sure, so the rule is
  identical to the old one. Nothing gets worse for the single-sound case.

Code: `DirectionTracker.classDirection` (Direction.swift) and `SourceFusion.fuse`
(SourceFusion.swift).

## Turning it on

`DetectionEngine(..., mode: .allBoxes)`. The app does this in `LiveSession.swift`. The default
for the library is still `.loudestBox` (the original behaviour), so nothing else changes.

| | `.loudestBox` | `.allBoxes` |
|---|---|---|
| Audio streams | 1 box | 4 boxes |
| Model runs | 1 per 0.1 s | up to 4 per 0.1 s (a quiet box skips it) |
| Two sounds at once | one shared arrow | one arrow each |
| Bluetooth | ~64 kbit/s | ~4 × 64 kbit/s |
| Battery | baseline | higher on the 3 extra boxes |

No firmware change is needed: each box already starts and stops audio on its own when the phone
writes `control`.

## What it does not fix

- **Two sounds of the same type** (two dogs) are still one "dog". The model names classes, not
  individual sources.
- **A quiet sound under a very loud one** can still be missed. The model hears every mix; this
  mode only stops mixes from sharing one arrow.
- **Direction is still 4-box rough**, not an exact angle.

## What to check on real hardware

This was written and unit-tested without hardware or a Mac build, so these are the open checks:

1. **Bluetooth.** Four ADPCM streams at once. Watch `audioMissed` per box
   (`soundring-listen` or the debug status). If packets drop a lot, fall back to `.loudestBox`.
2. **Phone load.** Up to 40 model runs a second. Check heat and battery over a 10 minute run.
3. **Two-source test.** Siren from the left on a speaker, baby-cry clip from behind on another;
   confirm two events with two different arrows. Then re-run with `.loudestBox` to see the old
   single arrow.
4. **Mic differences.** Every box peak-normalises its own window, so a quieter mic doesn't lose
   its vote. Confirm this on the real mics.
