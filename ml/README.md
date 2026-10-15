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
- **Calibrated thresholds** (`models/thresholds.json`): chosen per class from the data. Safety
  sounds (siren, alarm, glass, horn, baby) are tuned for recall; low-stakes sounds for precision.
- **Priority scoring** (`config.CLASS_PRIORITY`, used by the Pi and demo): when several sounds
  are detected, `priority × confidence × loudness` decides which one gets the ring. A loud dog
  loses to a quieter car horn.
- **Persistence** (`PERSIST_FRAMES`): a sound must show up on 2 consecutive updates before it
  lights, which removes one-frame flickers at the cost of ~0.25 s latency.

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
