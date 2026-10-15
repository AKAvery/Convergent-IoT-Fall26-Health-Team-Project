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
clip accuracy: 92.6%

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
| `data/my_clips/<label>/*.wav` | **your own recordings** (optional, see below) | yours |

The datasets are not committed (1.4 GB). Download them with:

```bash
cd ml/data
git clone --depth 1 https://github.com/karolpiczak/ESC-50
git clone --depth 1 https://github.com/Jakobovski/free-spoken-digit-dataset FSDD
```

The YAMNet backbone (`models/yamnet_embedding_metadata.tflite`) *is* committed; it came
from TensorFlow's own repo.

## Run it

```bash
pip install tensorflow-cpu soundfile resampy scikit-learn
cd ml
python3 prepare_data.py        # builds work/manifest.csv, prints class counts
python3 extract_embeddings.py  # ~4 min on a laptop, writes work/embeddings.npz
python3 train_head.py          # ~1 min, writes models/sound_head.tflite + labels.json
cp models/sound_head.tflite models/labels.json ../pi/
```

## Add your own sounds (recommended)

The biggest accuracy win is recording the *actual* doorbell, dryer buzzer, smoke alarm,
etc. that the user will hear. Phone recordings are fine.

1. Make `data/my_clips/<label>/` — the label can be an existing one (`knock`) or new (`doorbell`, `dryer`).
2. Drop 20–40 WAV clips in, 2–5 seconds each, from different distances and rooms.
3. Re-run the three scripts. New labels are picked up automatically and added to `labels.json`.
4. If you add a new label, add a colour for it in `pi/sound_ring.py` → `HIGHLIGHT`.

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
