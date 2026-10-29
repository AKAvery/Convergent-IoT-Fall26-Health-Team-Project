# Does the classifier survive IMA ADPCM?

Same pipeline, same clips, same seeds, run back to back in one process: **ref** = default eval (float audio), **adpcm** = every detector stream rounded to int16 and passed through `ml/adpcm.py` encode -> decode (4-bit IMA, 320-sample packets). Produced by `ml/eval_adpcm.py`.

params: `hop_s=0.1, buffer_s=1.0, gate_db=-70.0, gate_window_s=0.1, persist=5, other_veto=True, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.1, loud_ref_db=-60.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`  
test split: 336 clips

## Decision rule (docs/week1-tasks.md A2)

Propose another codec if any safety class (siren, alarm, car_horn, glass_break) loses more than 0.05 caught (checked at -20 dBFS and every level of the sweep) or big-label accuracy drops more than 2 points.

- big-label accuracy (pooled over target clips at -20 dBFS): **0.988 -> 0.989** (+0.1 points)
- result: **passed**, no safety class lost more than 0.05 caught at any level

## Per class at -20 dBFS (ref -> adpcm)

| class | n | caught | wrong label | wrong shown big | big-label acc | onset median s |
|---|---|---|---|---|---|---|
| alarm **(safety)** | 8 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 0.70 -> 0.75 |
| appliance | 16 | 0.94 -> 0.88 ⚠ | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 1.20 -> 1.20 |
| baby_cry | 8 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 1.95 -> 1.95 |
| car_horn **(safety)** | 8 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 0.95 -> 0.95 |
| cat | 8 | 1.00 -> 1.00 | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.98 -> 0.98 | 0.75 -> 0.70 |
| clap | 8 | 1.00 -> 1.00 | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.99 -> 0.99 | 0.60 -> 0.75 |
| dog | 8 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 0.70 -> 0.70 |
| footsteps | 8 | 0.75 -> 0.75 | 0.38 -> 0.50 | 0.38 -> 0.50 | 0.79 -> 0.81 | 1.55 -> 1.55 |
| glass_break **(safety)** | 8 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 0.80 -> 0.95 |
| knock | 8 | 1.00 -> 1.00 | 0.12 -> 0.25 | 0.12 -> 0.12 | 0.99 -> 0.99 | 0.85 -> 0.75 |
| siren **(safety)** | 8 | 1.00 -> 1.00 | 0.12 -> 0.12 | 0.12 -> 0.12 | 1.00 -> 1.00 | 1.00 -> 1.25 |
| speech | 120 | 1.00 -> 1.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.00 -> 1.00 | 0.50 -> 0.50 |
| **mean** | | 0.97 -> 0.97 | 0.07 -> 0.09 | | 0.99 -> 0.99 | |

'other' test clips with any target fired: 0.18 -> 0.22

## Level sweep: caught rate per class (ref -> adpcm)

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm (safety) | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| appliance | 0.94 -> 0.94 | 0.94 -> 0.94 | 0.94 -> 0.94 | 0.94 -> 0.94 | 0.94 -> 1.00 |
| baby_cry | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 0.88 |
| car_horn (safety) | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| cat | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| clap | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 0.88 -> 0.75 |
| dog | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 0.88 |
| footsteps | 0.75 -> 0.88 | 0.75 -> 0.75 | 0.75 -> 0.88 | 0.75 -> 0.62 | 0.75 -> 0.62 |
| glass_break (safety) | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| knock | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| siren (safety) | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 | 1.00 -> 1.00 |
| speech | 0.94 -> 0.98 | 0.99 -> 1.00 | 0.99 -> 0.99 | 0.98 -> 0.99 | 0.99 -> 0.99 |
| **mean** | 0.95 -> 0.98 | 0.98 -> 0.99 | 0.98 -> 0.99 | 0.98 -> 0.98 | 0.98 -> 0.96 |

## Level sweep: wrong-label rate per class (ref -> adpcm)

| class | -10 dB | -20 dB | -30 dB | -40 dB | -50 dB |
|---|---|---|---|---|---|
| alarm (safety) | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |
| appliance | 0.06 -> 0.06 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |
| baby_cry | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.12 -> 0.25 | 0.12 -> 0.12 | 0.12 -> 0.00 |
| car_horn (safety) | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.12 -> 0.00 |
| cat | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.12 -> 0.12 |
| clap | 0.12 -> 0.12 | 0.12 -> 0.12 | 0.25 -> 0.25 | 0.12 -> 0.12 | 0.00 -> 0.00 |
| dog | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |
| footsteps | 0.38 -> 0.50 | 0.38 -> 0.50 | 0.38 -> 0.38 | 0.38 -> 0.50 | 0.50 -> 0.50 |
| glass_break (safety) | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |
| knock | 0.00 -> 0.12 | 0.12 -> 0.25 | 0.12 -> 0.25 | 0.00 -> 0.12 | 0.00 -> 0.12 |
| siren (safety) | 0.25 -> 0.12 | 0.12 -> 0.25 | 0.12 -> 0.00 | 0.00 -> 0.12 | 0.12 -> 0.25 |
| speech | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |
| **mean** | 0.04 -> 0.04 | 0.03 -> 0.05 | 0.04 -> 0.05 | 0.03 -> 0.04 | 0.04 -> 0.04 |

## eval_pipeline.compare(ref, adpcm): false fires, overlap, OOV, regression guard

new:  `hop_s=0.1, buffer_s=1.0, gate_db=-70.0, gate_window_s=0.1, persist=5, other_veto=True, other_veto_margin=0.15, veto_exempt_priority=8, label_margin=0.1, loud_ref_db=-60.0, loud_floor=0.2, input_gain_db=0.0, clip_level=0.99`

## Per class at -20 dBFS

| class | caught base -> new | wrong base -> new |
|---|---|---|
| alarm | 1.00 -> 1.00 | 0.00 -> 0.00 |
| appliance | 0.94 -> 0.88 **REGRESSION** | 0.00 -> 0.00 |
| baby_cry | 1.00 -> 1.00 | 0.00 -> 0.00 |
| car_horn | 1.00 -> 1.00 | 0.00 -> 0.00 |
| cat | 1.00 -> 1.00 | 0.12 -> 0.12 |
| clap | 1.00 -> 1.00 | 0.12 -> 0.12 |
| dog | 1.00 -> 1.00 | 0.00 -> 0.00 |
| footsteps | 0.75 -> 0.75 | 0.38 -> 0.50 |
| glass_break | 1.00 -> 1.00 | 0.00 -> 0.00 |
| knock | 1.00 -> 1.00 | 0.12 -> 0.25 |
| siren | 1.00 -> 1.00 | 0.12 -> 0.12 |
| speech | 1.00 -> 1.00 | 0.00 -> 0.00 |

## Mean caught / wrong per level

| level | caught base -> new | wrong base -> new |
|---|---|---|
| -50 dB | 0.98 -> 0.96 | 0.04 -> 0.04 |
| -40 dB | 0.98 -> 0.98 | 0.03 -> 0.04 |
| -30 dB | 0.98 -> 0.99 | 0.04 -> 0.05 |
| -20 dB | 0.98 -> 0.99 | 0.03 -> 0.05 |
| -10 dB | 0.95 -> 0.98 | 0.04 -> 0.04 |

## False fires per minute

| source | total base -> new | safety | babies | privacy | household |
|---|---|---|---|---|---|
| other clips | 2.40 -> 2.90 **REGRESSION** | 0.50 -> 0.60 | 0.00 -> 0.00 | 0.00 -> 0.00 | 1.90 -> 2.30 |
| background only | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 | 0.00 -> 0.00 |

## Overlap

at least one 0.98 -> 0.97, both 0.33 -> 0.37, third class 0.04 -> 0.03


## OOV

clips with any fire: 55/304 -> 62/304


## Regression guard

**FAILED**: appliance: caught 0.94 -> 0.88; other clips: false fires/min 2.40 -> 2.90

---

## Notes (hand-written, 2026-10-29; re-running `eval_adpcm.py` regenerates everything above this line)

- **The reference reproduces the committed default.** The ref run's confusion and false-fire sections are
  identical to `work/eval_default.md` (2026-10-17), so the baseline is the shipped pipeline.
- **What flipped, clip by clip (-20 dBFS confusion):** 1 appliance clip missed (0.94 -> 0.88 is 1 of 16);
  1 footsteps clip and 1 knock clip gained a wrong label; 1 siren clip gained `alarm` while another siren
  clip lost it. On the 126 'other' clips, 2 stopped firing and 6 started. No safety clip was missed
  at any level. Small n: safety classes have 8 clips each, so one clip = 0.125. The 0.05 rule therefore
  really means "no safety clip may be lost", and that holds.
- **Control: is it ADPCM, or any noise at this level?** The same eval with white noise added at the same
  per-packet power as the ADPCM error (SNR ~22-24 dB, script outside the repo) gave: appliance caught
  0.94 -> 1.00, siren wrong 0.12 -> 0.25, baby_cry wrong 0.00 -> 0.12, false fires on 'other' clips
  2.40 -> **3.60**/min, OOV 55 -> 60/304. That is the same kind of drift, and the false fires are worse
  than ADPCM's. These flips come from the model's sensitivity to a ~22 dB-SNR channel, not from anything
  specific to IMA ADPCM, so another codec at the same SNR would not fix them.
- **Harness guard vs. A2 rule.** `eval_pipeline.compare`'s general guard (any class -0.05 caught, or
  +0.2 false fires/min) fails: appliance -0.06 (1 clip), 'other' false fires +0.50/min. The A2 decision
  rule (safety classes and big-label accuracy) passes. Big-label accuracy is 0.988 -> 0.989.
- **Onset is a little later on some safety classes** (median, caught clips): siren 1.00 -> 1.25 s,
  glass_break 0.80 -> 0.95 s, alarm 0.70 -> 0.75 s. Reported only; there is no rule for it.
- Digital attenuation only. No room, mic or BLE packet loss. The codec is applied to the whole stream,
  including the 2 s background pads, with the encoder starting at state (0, 0).

## Verdict

**Keep IMA ADPCM.** Under the A2 decision rule it passes cleanly. No safety class (siren, alarm,
car_horn, glass_break) lost a single caught clip at -20 dBFS or anywhere in the -10 to -50 dBFS sweep,
and big-label accuracy held (0.988 -> 0.989). The costs are real but small. One appliance clip is
missed, 'other' clips cause about 0.5 more false fires per minute (2.40 -> 2.90), mean wrong-label goes
0.07 -> 0.09, and siren/glass_break onsets are 0.15-0.25 s later. These trip the harness's stricter
general guard. However, the matched-noise control produces the same drift (false fires 3.60/min), so
the cause is the model's tolerance to a ~22 dB SNR channel, not something a different 4-bit codec would
avoid. Anything meaningfully cleaner needs more bits than the 169-byte / 50 Hz packet carries; 8-bit
mu-law would need 320 bytes per packet. If the false-fire rise matters, the lever that fits the
no-retraining rule (docs/architecture.md) is to re-tune thresholds on ADPCM streams with this harness,
the same way the -20 dBFS thresholds were tuned. Either way, the contract can freeze with IMA ADPCM.
