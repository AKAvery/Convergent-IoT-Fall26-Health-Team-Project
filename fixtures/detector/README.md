# Detector fixtures

Reference outputs of the Python detector (`demo/detector.py`, default params, preset `all`)
for the Swift port. C4's `Classifier` must match `probs` within 1e-4. A5's `Detector` must
match `gated`, `hits` and `label` exactly.

Regenerate or verify (from `ml/`, with the repo venv):

```bash
python3 export_detector_fixtures.py           # rewrite everything here
python3 export_detector_fixtures.py --check   # re-run Python and confirm every file is reproduced exactly
```

The model files are `ml/models/` (byte-identical to `pi/`); their SHA-256 hashes are in
`manifest.json`, so a test can tell when the fixtures are stale.

## Files

| File | What |
|---|---|
| `manifest.json` | List of clips, the detector settings, model hashes, tolerances |
| `NN_<name>.json` | One clip: what went in, and the detector's output for every 0.1 s step |
| `NN_<name>.bin` | That clip's input audio: raw float32, little-endian, mono, 16 kHz, no header |

To read a `.bin`: in Swift, `Data(contentsOf:)` then load it as `[Float]`
(`data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }`; Apple platforms are
little-endian). In Python, `np.fromfile(path, "<f4")`. To listen to one:
`sf.write("x.wav", np.fromfile(path, "<f4"), 16000)`.

The audio is the detector's exact input, after resampling to 16 kHz, setting the level and adding
background. Swift does not resample or add anything. Its length is a whole number of hops.

## The 30 clips

All clips come from the held-out **test** split, the same rows `ml/eval_pipeline.py` uses
(`work/manifest.csv` with `split == "test"`: ESC-50 fold 5, FSDD speaker `theo`). They are
picked with a fixed seed (2026).

| Kind | Count | Stream |
|---|---|---|
| `target` | 24 (2 per class) | 2 s of white noise at −70 dBFS RMS, the clip at −20 dBFS peak, 2 s of noise. This is `eval_pipeline`'s `confusion` stream. |
| `other` | 2 | ESC-50 "other" test clips, same stream |
| `noise` | 1 | 4 s of white noise at −30 dBFS RMS |
| `silence` | 1 | 3 s of exact zeros: gated at every step |
| `quiet_noise` | 1 | 4 s of white noise at −80 dBFS RMS: gated at every step |
| `quiet_target` | 1 | A siren clip at −78 dBFS peak over −90 dBFS noise: a real sound below the gate, gated at every step |

Note that the −70 dBFS padding sits just above the −70 dBFS gate (its `level_db` is between
−69.9 and −69.6, because `level_db` is the loudest 100 ms sub-window). So the padding is **not** gated,
and the model runs on noise there. That matches the eval harness.

## `manifest.json`

| Field | Meaning |
|---|---|
| `format_version` | 1 |
| `generator`, `seed`, `split` | Where it came from |
| `models.dir`, `models.sha256` | Model files used, and the SHA-256 of each |
| `detector` | Same block as in each clip (see below) |
| `tolerances` | `probs_abs` = 1e-4. Decisions must match exactly. |
| `fragile_eps` | The margins used to flag `fragile` steps (see below) |
| `coverage_clips` | How many clips reach each decision path: `not_ready`, `gated_by_level`, `waiting_for_persist`, `other_veto`, `hit`, `multiple_hits`, `label`, `label_safety_exempt`, `label_withheld_by_margin` |
| `clips[]` | `id`, `kind`, `true_label`, `json`, `audio`, `num_samples`, `num_steps`, `fired` (classes that were ever in `hits`), `big_labels` (classes that were ever `label`), `gated_steps`, `fragile_steps` |

## Clip JSON

| Field | Meaning |
|---|---|
| `format_version` | 1 |
| `id` | Same as the file name |
| `kind` | See the table above |
| `true_label` | The clip's class (`null` for silence and quiet noise) |
| `source` | `path` (relative to the repo), `offset_s`, `duration_s` (0 = whole file), `dataset`; `null` for synthetic clips |
| `stream` | How the input was built, in words |
| `audio` | `file`, `dtype` (`float32`), `byte_order` (`little`), `channels` (1), `sample_rate` (16000), `num_samples`, `sha256` of the raw bytes |
| `detector` | Settings, see below |
| `num_steps` | `num_samples / hop_samples` |
| `fragile_steps` | Indices of steps that have a `fragile` entry |
| `steps[]` | One entry per 0.1 s hop, in order, starting from a freshly reset detector |

### `detector`

| Field | Meaning |
|---|---|
| `preset` | `all`: every hit can become the big label |
| `sample_rate`, `hop_samples` (1600), `buffer_samples` (16000), `window_samples` (15600) | Streaming shape |
| `params` | Every `DetectorParams` field: `hop_s`, `buffer_s`, `gate_db` (−70), `gate_window_s` (0.1), `persist` (5), `other_veto`, `other_veto_margin` (0.15), `veto_exempt_priority` (8), `label_margin` (0.10), `loud_ref_db` (−60), `loud_floor` (0.2), `input_gain_db` (0), `clip_level`, `sustain` (`{"speech": 0.5}`: once fired, a class stays on while its probability is at least this) |
| `labels` | Class names in model output order. `probs` and `streak` use this order. |
| `thresholds` | Per class, as the float32 value the detector compares against (`thresholds.json` cast to float32) |
| `class_priority` | Priority per class. A class that isn't listed (`other`) counts as 1. |
| `presets` | Classes allowed per preset (`null` = all) |

### `steps[]`

| Field | Meaning |
|---|---|
| `i` | Step index. This step's block is samples `[i*1600, (i+1)*1600)`. |
| `t` | Seconds of audio fed so far, `(i+1) * 0.1` |
| `ready` | The 1 s buffer is full (false for steps 0–8; the buffer starts as zeros) |
| `level_db` | `20*log10(max over the 10 sub-windows of 1600 samples of their RMS + 1e-9)`, over the 1 s buffer. Computed even when not ready. Exact zeros give −180. |
| `gated` | `!ready || level_db < gate_db`. When true, the model isn't run, `probs` is `null` and `hits` is empty. |
| `probs` | 13 sigmoid outputs in `labels` order. They are float32 values written as decimals that round-trip exactly, so decode them into `Float`. |
| `hits` | Classes that fired this step, sorted by `score`, highest first: `{label, conf, score}`. `conf` is the probability, and `score = priority * conf * loud`, with `loud = clamp((level_db + 60) / 30, 0.2, 1)`. The labels and their order must match exactly; `conf` and `score` only within tolerance. |
| `label` | The big label (top hit for the preset, unless the label margin withholds it), or `null` |
| `conf` | Its probability (0 when `label` is null) |
| `streak` | Each class's persistence counter after this step, in `labels` order (`other` is always 0). Not part of the contract, but useful for debugging A5. |
| `label_by_preset` | Only on steps that weren't gated: what the big label would be under each other preset (`safety`, `babies`, `privacy`, `household`) for the same hits |
| `fragile` | Only present when some comparison in this step is closer to its boundary than Swift can be expected to reproduce: `gate` (level within 0.01 dB of the gate), `threshold:<class>` or `veto:<class>` or `label_margin` (within 1e-4 in probability), `other_top` (`other` and the top class within 1e-4), `hit_order` (the top two scores within 1e-3) |

## How to test against these

1. **Decision rules (A5), exact.** Replay each clip's `level_db` and `probs` through the
   Swift decision code: gate, then thresholds, veto, persistence, label. Compare `gated`,
   the `hits` labels in order, and `label` at every step. This isolates A5 from model
   float noise, so it must match on all 30 clips, including fragile steps.
2. **Classifier (C4), within 1e-4.** Rebuild the ring buffer from the `.bin` (or take the
   last 16000 samples fed up to step `i`), run Swift's `Classifier`, and compare with `probs`
   at every step that wasn't gated.
3. **End to end.** Feed the `.bin` in 1600-sample blocks to the Swift `Detector`. Decisions
   should match exactly. A difference can only be legitimate at or after a step listed in
   `fragile_steps`, because a flipped comparison changes a streak, and the streak carries
   forward.

## Details the Swift port must copy exactly

- **The peak normalisation uses the whole 1 s buffer.** `Classifier.probs` takes the peak of all
  16000 samples, scales the buffer by `x / peak * 0.5`, then keeps the last 15600 samples. So
  a peak in the first 400 samples (25 ms), which YAMNet never sees, still sets the scale. In
  float32, divide and then multiply; a silent buffer (peak 0) is left unscaled.
- **`level_db` arithmetic:** float32 squares, a float32 mean per 1600-sample sub-window, a
  float32 square root, the max of the 10, then `20*log10(Double(x) + 1e-9)` in double.
  NumPy sums float32 pairwise, so a naive Swift float loop differs by about 1e-6 relative,
  which is a few 1e-5 dB. That only matters when `level_db` is within that much of −70
  (flagged `gate`).
- **Veto and label-margin sums are float32** (NumPy 2 keeps `float32 + python float` in
  float32): `p[i] < p[other] + Float(0.15)` and `p[top] < maxRival + Float(0.10)`, with
  `p[i] < thr[i]` as the threshold test (so a probability exactly equal to its threshold
  passes).
- **`other` is "top"** when `argmax(probs)` is `other`. On a tie, the first index wins (NumPy).
- **The score is double:** `Double(priority) * Double(p) * loud`, where `loud` is double. Hits are
  sorted stably by descending score.
- **Streaks:** a class that is below its threshold, or vetoed, resets to 0. Otherwise it goes
  up by 1 and joins `hits` once it is ≥ `persist`. Streaks don't change on gated steps, and
  `other` never gets one.
