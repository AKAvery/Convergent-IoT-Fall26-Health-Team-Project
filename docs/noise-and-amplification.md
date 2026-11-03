# Room noise and quiet sounds: what helps, what doesn't

Researched and measured 2026-11-03 on the front box (XIAO ESP32-C3 + INMP441). The question
was: can we **amplify quiet sounds while quieting room noise**, the way AirPods and hearing aids
do, to catch more sounds? Rule we kept to: **no retraining** of YAMNet or our head, and
**no new wrong labels** (judged with the eval harness).

## Short answer

- **Turning the volume up does nothing.** The classifier already scales every 1 s window to the
  same peak before YAMNet (`Classifier.probs` in `demo/detector.py`, same in Swift). A quiet sound
  is already shown to YAMNet at full volume, together with the room noise in that window.
- **Room noise is our biggest accuracy problem.** With real room noise underneath, we catch 0.85
  of sounds at −20 dBFS, 0.64 at −30, 0.35 at −40 and 0.08 at −50. Roughly: every 10 dB quieter
  (about 3x farther away) halves what we catch.
- **Single-mic noise reduction makes it worse** (more wrong labels), as the research predicts.
- **What actually helps is more signal over noise at the mic**: use the best of the 4 boxes, and
  consider a **second mic per box** (what AirPods and hearing aids do).

## What we measured

### The test

The normal eval harness (`ml/eval_pipeline.py`) only puts background noise in the 2 s gaps
**before and after** each clip, never **under** it. So it says ~0.98 of sounds are caught even
at −40 dBFS. It doesn't test noise at all.

We built a noisy version (scratch script, not yet in the repo): the harness's own test clips
(all 96 non-speech target clips, 16 of the 120 speech clips, 40 "other" clips) with **real room noise from
the front box mixed underneath the whole stream**, at the room's real level (−42 dBFS). Then
the box chain (DC filter, 16-bit, IMA ADPCM), then our detector with shipping settings, scored
with the harness's own `score_clip` and `episodes`. Two noises: the 44 s real recording, and
steady noise with the same spectrum.

### Results (real room noise)

| What we tried | Caught at −20 / −30 / −40 / −50 dBFS | Wrong-label rate | Verdict |
|---|---|---|---|
| **Today's chain** | 0.85 / 0.64 / 0.35 / 0.08 | 0.10–0.14 | baseline |
| +12 dB gain | identical to the line above | identical | does nothing (level is normalised) |
| 100 Hz high-pass on the box | 0.84 / 0.64 / 0.35 / 0.07 | 0.08–0.13 | no help; on steady noise it tripled "appliance" |
| Mild spectral noise reduction | 0.88 / 0.68 / 0.33 / 0.08 | **0.15–0.17** | more wrong labels |
| Strong spectral noise reduction | 0.90 / 0.62 / 0.33 / 0.08 | **0.44–0.64**, 9 false fires/min on noise alone (mostly clap) | much worse |

On steady (synthetic) noise the strong reducer looked great (wrong labels → 0), and the mild one
made "appliance" fire on almost everything. Steady noise isn't what a real room sounds like.

### Other findings

- **Most room-noise energy at the box is rumble below 100 Hz** (building, HVAC or handling),
  about 15 dB above the part YAMNet can use (it only looks at 125–7500 Hz). It doesn't confuse
  YAMNet, but it **inflates the box's level packets**, so picking the "loudest box" may follow
  rumble rather than the sound.
- **Apple's own Sound Recognition model is not better in noise.** iOS Sound Recognition uses the
  SoundAnalysis built-in classifier (303 labels). We ran it on the same 448 noisy files, mapped
  to our 12 classes (same box chain and noise; a different slice of the noise than the table
  above, so our −30 dBFS number differs a little):

| At a similar wrong-label rate | Clean | Noise −20 | Noise −30 | Noise −40 |
|---|---|---|---|---|
| **Ours** (caught) | **0.94** | **0.85** | **0.70** | **0.35** |
| Apple built-in, threshold 0.5 + 0.5 s persistence | 0.79 | 0.79 | 0.59 | 0.28 |

  Apple's model was a little better on quiet **safety** sounds. Adding its opinion for the 4 safety
  classes only (threshold 0.7) raised safety catch at −40 dBFS from 0.38 to 0.47, but wrong labels
  went up ~0.02 (siren vs alarm). Worth a bigger test, not shipping. Apple also says not to rely on
  Sound Recognition where you could be harmed
  ([AppleInsider](https://appleinsider.com/articles/23/04/18/apple-turns-on-homepods-smoke-alarm-recognition)).

**Caveats:** one room, 44 s of noise, 8 clips per non-speech class (16 for appliance), single runs. The direction of
every result held on both noise types; treat the exact numbers as rough.

## How AirPods and hearing aids do it

| Product | How it gets voice over noise |
|---|---|
| AirPods Pro: Conversation Boost | Two beamforming mics per earbud plus processing; independent testing measured ~5.5 dB SNR gain, mostly from the beamforming ([Apple](https://support.apple.com/en-ie/111834), [HearingTracker](https://www.hearingtracker.com/news/enable-conversation-boost), [Hearing Review](https://hearingreview.com/hearing-products/hearing-aids/psap/apple-airpods-pro-for-people-with-hearing-loss-in-noisy-environments)) |
| AirPods: Live Listen | Uses the iPhone as a remote mic you put near the talker: it wins by **moving the mic closer** ([Cook Children's](https://www.cookchildrens.org/health-resources/technology/airpods-hearing/)) |
| iPhone Voice Isolation | Keeps your voice, blocks the rest; speech-only ([Apple](https://support.apple.com/101993)) |
| Hearing aids: directional mics | Two mics 10–15 mm apart; ~5 dB directivity typical, ~6 dB theoretical max, 2–5 dB in real rooms ([US7764801](https://patents.google.com/patent/US7764801), [US8121309](https://image-ppubs.uspto.gov/dirsearch-public/print/downloadPdf/8121309), [Hearing Review](https://hearingreview.com/practice-building/practice-management/adaptive-directional-microphone-technology-and-hearing-aids-theoretical-and-clinical-implications)) |
| Hearing aids: neural noise reduction | Phonak DEEPSONIC, Oticon DNN 2.0: networks trained to separate **speech** from noise ([HearingTracker](https://www.hearingtracker.com/de/stories/news/phonak-unveils-groundbreaking-infinio-hearing-aids-and-ai-powered-audeo-sphere-infinio), [Oticon](https://www.oticon.com/-/media/oticon-us/main/download-center---myoticon---product-literature/intent/whitepapers/15500-0299---4d-sensor-technology-and-dnn-2-0-whitepaper.pdf?la=en)) |

### Why most of it doesn't carry over to us

1. **They serve human ears and speech; we serve a frozen classifier and non-speech sounds.**
   Speech denoisers keep speech and remove "everything else", which for us includes sirens,
   barks and breaking glass.
2. **Denoising that isn't trained with the model tends to hurt the model.** In speech recognition,
   single-channel enhancement often fails to help, or hurts, because of its artifacts; mixing some
   original audio back helps ([Wang et al.](https://arxiv.org/abs/1903.04567v2),
   [Iwamoto et al.](https://arxiv.org/abs/2201.06685)). Our measurements show the same.
3. **Beamforming is the part that does help recognizers** (a clean, linear mix of real mic signals;
   the standard front end in the CHiME challenges, e.g. [arXiv 1803.10109](https://arxiv.org/abs/1803.10109)).
   But it needs mics on **one clock** at a **fixed, small distance**. Our 4 boxes have separate
   clocks, Bluetooth jitter and moving spacing, so beamforming **across** boxes isn't practical
   ([Schmalenstroeer & Haeb-Umbach](https://www.uni-paderborn.de/fileadmin/asn/Publications/SchHaebITG2018.pdf)).
   Beamforming **inside** one box is possible, which is why the two-mic idea below exists.
4. **No published study** tests a beamformer or denoiser in front of a frozen sound-event
   classifier like ours. Our own eval is the only way to know.

## Why two mics per box

| | One mic per box (today) | Mics on different boxes | **Two mics on one box** |
|---|---|---|---|
| Same clock? | n/a | No (separate ESP32s, BLE jitter) | **Yes**: both on one I2S bus |
| Fixed spacing? | n/a | No, 0.3–1 m and moving | **Yes**: ~21 mm |
| Can it beamform? | No | Not practically | **Yes** (like a hearing aid) |

- **Wiring:** two INMP441s share SCK, WS and SD; one has L/R to GND (left slot), the other L/R to
  3V3 (right slot). Each mic goes quiet in the other's slot, so the bus carries a sample-synced
  stereo pair. Our firmware already reads both slots (`firmware/include/mic.h`).
- **Why not 3 or 4 mics per box:** one I2S data line carries exactly 2 channels, and the INMP441
  can't do TDM. A third mic needs another I2S data line and much tighter mic matching, for little
  extra gain at this size. Two mics gets most of what's possible.
- **The beam:** a fixed first-order differential beam (cardioid-like), the hearing-aid kind. At
  **21.4 mm spacing the delay is exactly 1 sample at 16 kHz**, so it's delay, subtract and a simple
  EQ: under 1% of the C3's CPU, integer only. Delay-and-sum doesn't work at this spacing.
- **Point it along the body, not outward.** With the mic axis pointing out of the body, the body's
  reflection arrives in step with the direct sound and the beam turns back into an omni at low
  frequencies (our derivation, not measured). Hearing aids also run front-to-back along the head.
- **Expected gain:** about **2–4 dB SNR** in diffuse room noise (theoretical first-order max ~6 dB;
  the body already blocks the rear), mostly above ~500 Hz. By our recall curve that's roughly
  **15–30% more sounds caught** at −30/−40 dBFS. More against one noise source sitting in the
  beam's null. Real but modest.
- **Risks:** cheap MEMS mics differ in sensitivity (the INMP441's sibling ADMP441 lists ±3 dB,
  [ADI](https://www.analog.com/media/en/technical-documentation/obsolete-data-sheets/ADMP441.pdf));
  1 dB of mismatch wrecks the low-frequency null, so each box needs a gain trim. The beam changes
  each box's loudness, so **all 4 boxes need identical beams** or direction-finding (which compares
  loudness, see `docs/body-boxes-plan.md`) gets skewed. The EQ must be right or YAMNet hears a
  tilted spectrum.
- **Cost:** ~$1–2 per extra mic (we have 5 for 4 boxes, so order ~3 more), up to 1.4 mA more
  current, a box at least ~21 mm long on the mic axis, and ~1–2 days of firmware.

## Recommendations, in order

1. **Use the 4 boxes better (no new hardware).** Choose the streaming box by its level **above
   100 Hz** (or in-band SNR), not raw peak, so rumble doesn't pick the box. Later, consider running
   the classifier on all 4 boxes and combining results: the body blocks ~8 dB from behind, so some
   box always hears better ([arXiv 1903.02094](https://ar5iv.labs.arxiv.org/html/1903.02094)). That
   needs all 4 streaming (~34 KB/s over BLE) and more battery: a team decision.
2. **Add the noisy eval to the repo** and tune per-class thresholds under noise. No retraining,
   and it's the yardstick for everything else.
3. **Prototype one two-mic box** and record it through the noisy eval before wiring all four. A
   two-channel recording settles the real gain, the mic matching and which axis works.
4. **Placement:** shoulder and upper-body spots beat the chest (less body shadow); spread boxes
   front, back and sides. A better mic model won't matter: the room is ~42 dB above the INMP441's
   own noise ([TDK](https://invensense.tdk.com/digital/inmp441)).

**Not worth doing:** more gain, single-mic spectral denoisers, speech AI denoisers (Voice
Isolation, RNNoise, DeepFilterNet), PCEN (needs retraining).

## Open questions

- **Which board?** `docs/hardware-bom.md` records 6 **XIAO ESP32-S3** boards ordered 2026-10-22,
  but the board in use and `firmware/platformio.ini` are **ESP32-C3**. The S3 has much more
  processing headroom (FPU, vector instructions, Espressif's audio front-end library); the
  two-mic beam fits on either.
- How much the real gain from two mics is on our clips (needs a two-mic recording).
- Whether combining all 4 boxes beats picking the best one, by how much, and at what battery cost.
