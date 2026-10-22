# Sound classifier training

Trains the small model that tells the Pi *what* a sound is. The pipeline is:

```
audio clip ──> YAMNet backbone (frozen, Google) ──> 1024-d embedding ──> our head ──> label
```

YAMNet was pretrained by Google on 2 million YouTube clips (AudioSet). We keep it frozen
and only train a tiny classifier on top, so training takes ~1 minute on a laptop and the
result is accurate on our 12 target sounds instead of 521 random ones.

## Results (held-out ESC-50 fold 5 + unseen speaker)

```
single-sound clip accuracy: 93.8%
two-sound mixtures: at least one detected 95%, both detected 30%

              precision  recall
alarm           1.00     1.00
siren           1.00     1.00
speech          1.00     1.00
baby_cry        0.80     1.00
car_horn        0.80     1.00
dog             0.89     1.00
cat             1.00     0.88
knock           0.88     0.88
appliance       0.71     0.94
clap            1.00     0.75
glass_break     0.62     1.00
footsteps       0.58     0.88
other           0.97     0.84
```

Full confusion matrix in `work/report.txt` after you run training.

## Data (all free)

| Source | Used for | License |
|---|---|---|
| [ESC-50](https://github.com/karolpiczak/ESC-50) | dog, cat, baby cry, knock, glass, siren, car horn, clap, footsteps, alarm, vacuum/washer, + "other" | CC BY-NC |
| [Free Spoken Digit Dataset](https://github.com/Jakobovski/free-spoken-digit-dataset) | speech (6 real speakers) | CC BY-SA |
| [DEMAND](https://zenodo.org/records/1227121) *(optional)* | real rooms/streets as "other" + noise for augmentation | CC BY-SA |
| [MUSAN](https://www.openslr.org/17/) *(optional)* | noise, music ("other") and extra speech | CC BY |
| `data/my_clips/<label>/*.wav` | **your own recordings** (optional, see below) | yours |

The datasets are not committed. Download them with:

```bash
bash download_datasets.sh          # ESC-50 + FSDD (~1.5 GB, required)
bash download_datasets.sh --all    # + DEMAND + MUSAN (~13 GB, better background rejection)
```
DEMAND/MUSAN are picked up automatically by `prepare_data.py` if the folders exist.

The YAMNet backbone (`models/yamnet_embedding_metadata.tflite`) *is* committed; it came
from TensorFlow's own repo.

## Run it

```bash
pip install tensorflow soundfile resampy scikit-learn sounddevice
cd ml
python3 prepare_data.py        # builds work/manifest.csv, prints class counts
python3 extract_embeddings.py  # ~4 min on a laptop, writes work/embeddings.npz
python3 train_head.py          # ~1 min, writes models/sound_head.tflite + labels.json
cp models/sound_head.tflite models/labels.json ../pi/
```

## Add your own sounds (recommended)

The biggest accuracy win is recording the *actual* doorbell, dryer buzzer, smoke alarm,
etc. that the user will hear. Phone recordings are fine.

1. `python3 record_clips.py clap` (or `doorbell`, `dryer`, any label). Press Enter to record
   each 2 s clip. Do 20–40, from different distances and spots in the room. Or drop WAVs into
   `data/my_clips/<label>/` yourself.
3. Re-run the three scripts. New labels are picked up automatically and added to `labels.json`.
4. If you add a new label, add a colour for it in `pi/sound_ring.py` → `HIGHLIGHT`.

## How it stays robust in real rooms

- **Augmentation** (`extract_embeddings.py`): every training clip also gets noisy copies mixed
  with random background at 0–20 dB SNR, clap/knock clips get isolated single hits pasted on
  background (so one clap counts, not just applause), and clips get mixed with a second sound
  with both labels on, so overlapping sounds can both be detected.
- **Multi-label head** (`train_head.py`): sigmoid outputs, one yes/no per class, instead of
  softmax picking a single winner.
- **Calibrated thresholds** (`models/thresholds.json`): chosen per class from the data, under the
  streaming decision rule (see "Evaluating the live pipeline"). Safety sounds are tuned for recall
  (F-beta with beta 2), low-stakes sounds for precision.
- **Priority scoring** (`config.CLASS_PRIORITY`, used by the Pi and demo): when several sounds
  are detected, `priority × confidence × loudness` decides which one gets the ring. A loud dog
  loses to a quieter car horn.
- **Persistence** (`DetectorParams.persist`): a sound must show up on consecutive updates before
  it fires. Measured with `eval_pipeline.py`: the time span of evidence matters more than the
  count, so a shorter hop needs a higher persist to keep wrong labels down.

## Evaluating the live pipeline

Training accuracy says how good the head is on whole clips. What the user sees also depends on
the gate, hop, persistence and decision rule in `demo/detector.py`. `eval_pipeline.py` streams
the held-out test clips through that exact code and reports the two things we care about,
separately: **caught** (the true class fired while the clip played) and **wrong label** (another
class fired, and whether it was shown big).

```bash
pip install soundfile resampy tensorflow        # same venv as training
python3 eval_pipeline.py                        # default params -> work/eval_default.md
python3 eval_pipeline.py --compare              # baseline (old demo) vs default + regression guard
python3 eval_pipeline.py --compare --reuse-baseline --tag p5 --set persist=5   # try a change
python3 eval_pipeline.py --quick                # 2 clips/class smoke test (~10 s)
python3 eval_pipeline.py --playback             # through the real speakers + mic (needs sounddevice)
```

Sections of the report: streamed confusion at -20 dBFS (per class caught / wrong / big-label
accuracy / onset latency, plus a fired-class matrix), a level sweep from -10 to -50 dBFS, false
fires per minute on "other" clips and on pure background (per preset), out-of-vocabulary ESC-50
categories and what we called them, two-sound overlap, and a threshold sweep under the streaming
rule with an F-beta suggestion per class (nothing is written automatically).

`--compare` exits 1 and prints **REGRESSION** if any class loses more than 0.05 caught rate at
-20 dBFS or any source gains more than 0.2 false fires per minute. Every pipeline change should
pass it. Digital attenuation has no room or mic noise, so the quiet rows measure the gate and
ranking; `--playback` is the honest test of the laptop setup (and shows whether loud volumes
clip the mic).

**Onset latency (measured 2026-10-16).** How long after a sound starts the classifier first
fires, on 120 ESC-50 clips of our classes with 2 s of quiet before each, laptop CPU. Moved here
from the retired `docs/networking.md`.

| hop | persist | median | p90 | missed |
|---|---|---|---|---|
| 0.25 s (old demo) | 2 | 0.50 s | 1.05 s | 1 |
| 0.25 s | 1 | 0.25 s | 0.75 s | 0 |
| 0.10 s | 2 | 0.30 s | 0.81 s | 0 |
| 0.10 s | 1 | 0.20 s | 0.61 s | 0 |
| 0.05 s | 1 | 0.18 s | 0.61 s | 0 |

Inference is 0.6 ms per 1 s window. The classifier fires from the first fraction of a sound; it
does not need the window full. The demo ships hop 0.1 s with **persist 5**, not 2: this harness
showed hop 0.1 / persist 2 doubled wrong labels (0.13 to 0.24 of clips) and false fires (9.3 to
22.7 per minute). Persist 5 keeps the same 0.5 s evidence span as the old demo, so expect a median
near 0.5 s, not 0.3 s. That configuration's onset latency has not been measured separately.

**Thresholds.** `models/thresholds.json` (and the copy in `pi/`) currently hold values calibrated
with this harness under the streaming rule (2026-10-17: alarm 0.80, car_horn 0.75, siren 0.60,
glass_break 0.50, speech 0.80, ...). They are much higher than `train_head.py`'s clip-level
calibration (`models/thresholds_cliplevel.json`, kept so `--compare` can reproduce the old demo),
because under streaming every 0.1 s window gets a vote and the low clip-level values fired on
wind, trains, rain and cutlery. Clap, dog, knock and footsteps kept their old thresholds: raising
them cost recall. **`train_head.py` overwrites `thresholds.json` on retrain**; afterwards run
`eval_pipeline.py --write-suggested work/thr.json`, check `work/thr_safe.json` with
`--compare --thresholds work/thr_safe.json`, and copy it over if the guard passes.

When to retrain instead of tuning: a class with caught < 0.9 at -20 dBFS although the gate is
open, or wrong-label > 0.10 on unclipped input, is a model problem. Record 20–40 clips of it
(`record_clips.py`, below) and retrain; accept the new head only if `--compare --model-dir`
against the old model files passes the guard.

## Tuning

- `config.py` → `TARGETS`: which ESC-50 categories to use and what to call them.
- `config.py` → `OTHER_PER_FOLD`: how many background clips; raise it if the model
  false-fires on everyday noise, lower it if it misses real events.
- `train_head.py`: head is `Dense(256) → Dropout → Dense(n)`. It's deliberately small so
  it runs in a few ms on the Pi.

## Why not just use YAMNet's own 521 classes?

We tried it first (it still works, `pi/sound_ring.py` history has it). Problems: it spreads
confidence over near-duplicate classes ("Dog", "Bark", "Bow-wow", "Yip"), it has no idea what
"your dryer" sounds like, and 500 irrelevant classes mean more false positives. Training a
head on our 13 classes fixed all three and costs nothing at runtime.
