#!/usr/bin/env python3
"""
Train a small multi-label classifier head on YAMNet embeddings and export it for the Pi.

Multi-label (sigmoid) means each class is an independent yes/no, so "dog" and "speech"
can both be on at once instead of fighting for one softmax slot.

Outputs:
  models/sound_head.tflite   - the head (1024 -> n classes, sigmoid), ~0.3 MB
  models/labels.json         - class names in output order
  work/report.txt            - per-class precision/recall at the configured thresholds

Run: python3 train_head.py
"""
import json
import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from config import *

d = np.load(WORK_DIR / "embeddings.npz")
X, Y, split, clip_id = d["X"], d["Y"], d["split"], d["clip_id"]
labels = [str(l) for l in d["labels"]]
yi = Y.argmax(1)                 # primary label (for single-label eval / weighting)
multi = Y.sum(1) > 1             # overlap-augmented samples

tr, te = split == "train", split == "test"
# hold back 20% of overlap samples from training to measure overlap detection honestly
rng = np.random.RandomState(0)
ov_idx = np.where(tr & multi)[0]
ov_hold = rng.choice(ov_idx, size=len(ov_idx) // 5, replace=False)
tr[ov_hold] = False
print(f"{len(labels)} classes: {labels}")
print(f"train windows {tr.sum()}, test windows {te.sum()}")

# positive-class weighting so rare classes aren't drowned by "other"/"speech"
counts = np.bincount(yi[tr], minlength=len(labels)).astype(np.float32)
pos_w = np.clip(len(yi[tr]) / (len(labels) * counts), 0.5, 8.0)
sample_w = pos_w[yi[tr]]

tf.random.set_seed(0)
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(1024,)),
    tf.keras.layers.Dense(256, activation="relu"),
    tf.keras.layers.Dropout(0.4),
    tf.keras.layers.Dense(len(labels), activation="sigmoid"),
])
model.compile(optimizer=tf.keras.optimizers.Adam(1e-3), loss="binary_crossentropy")
model.fit(X[tr], Y[tr], sample_weight=sample_w, validation_data=(X[te], Y[te]),
          epochs=60, batch_size=64, verbose=0,
          callbacks=[tf.keras.callbacks.EarlyStopping(patience=8, restore_best_weights=True)])

# ------------------------------------------------- calibrate thresholds --
# Pick each class's threshold on TRAIN clips (not test) to maximise F-beta, where beta
# leans toward recall for high-priority (safety) sounds and toward precision for low ones.
p_tr = model.predict(X[tr], verbose=0)
tr_ids = np.unique(clip_id[tr])
Ptr = np.array([p_tr[clip_id[tr] == c].mean(0) for c in tr_ids])
Ttr = np.array([yi[tr][clip_id[tr] == c][0] for c in tr_ids])
thr = np.zeros(len(labels))
for j, l in enumerate(labels):
    pri = CLASS_PRIORITY.get(l, 1)
    beta = 2.0 if pri >= 7 else (1.0 if pri >= 4 else 0.7)
    best, best_t = -1, DEFAULT_THRESHOLD
    pos = Ttr == j
    for t in np.arange(0.1, 0.9, 0.02):
        det = Ptr[:, j] >= t
        tp = (det & pos).sum(); fp = (det & ~pos).sum(); fn = (~det & pos).sum()
        f = (1 + beta**2) * tp / max(1e-9, (1 + beta**2) * tp + beta**2 * fn + fp)
        if f > best: best, best_t = f, t
    thr[j] = round(float(best_t), 2)
(MODELS_DIR / "thresholds.json").write_text(json.dumps(dict(zip(labels, thr.tolist())), indent=1))

# ---------------------------------------------------------------- eval --
p_win = model.predict(X[te], verbose=0)

# per-clip: average windows, then (a) argmax for a confusion matrix, (b) thresholds for multi-label P/R
clip_ids = np.unique(clip_id[te])
P = np.array([p_win[clip_id[te] == c].mean(0) for c in clip_ids])
T = np.array([yi[te][clip_id[te] == c][0] for c in clip_ids])
argmax_acc = (P.argmax(1) == T).mean()
rep_argmax = classification_report(T, P.argmax(1), labels=range(len(labels)), target_names=labels, digits=3, zero_division=0)
cm = confusion_matrix(T, P.argmax(1), labels=range(len(labels)))

# multi-label view at the per-class thresholds (what the Pi actually does)
det = P >= thr
lines = ["per-class detection at calibrated thresholds (clip level, held-out test):",
         f"{'class':12s} {'thr':>4s} {'recall':>7s} {'precision':>10s} {'false+/clip':>12s}"]
for j, l in enumerate(labels):
    pos = T == j
    rec = det[pos, j].mean() if pos.any() else float("nan")
    prec = (pos & det[:, j]).sum() / max(1, det[:, j].sum())
    fp_rate = det[~pos, j].mean()
    lines.append(f"{l:12s} {thr[j]:4.2f} {rec:7.2f} {prec:10.2f} {fp_rate:12.3f}")

out = [f"argmax clip accuracy: {argmax_acc:.3f}", "", rep_argmax, "",
       "confusion matrix (argmax; rows = true, cols = predicted)",
       "              " + " ".join(f"{l[:5]:>5s}" for l in labels)]
for l, row in zip(labels, cm):
    out.append(f"{l:12s}  " + " ".join(f"{v:5d}" for v in row))
# overlap check: on held-back two-sound mixtures, how often are BOTH sounds detected?
Pov = model.predict(X[ov_hold], verbose=0) >= thr
both = np.mean([(Pov[k][Y[ov_hold][k] > 0]).all() for k in range(len(ov_hold))])
one = np.mean([(Pov[k][Y[ov_hold][k] > 0]).any() for k in range(len(ov_hold))])
lines += ["", f"overlap test ({len(ov_hold)} two-sound mixtures): at least one detected {one:.2f}, both detected {both:.2f}"]
out += [""] + lines
report = "\n".join(out)
print(report)
(WORK_DIR / "report.txt").write_text(report)

# -------------------------------------------------------------- export --
conv = tf.lite.TFLiteConverter.from_keras_model(model)
conv.optimizations = [tf.lite.Optimize.DEFAULT]
(MODELS_DIR / "sound_head.tflite").write_bytes(conv.convert())
(MODELS_DIR / "labels.json").write_text(json.dumps(labels, indent=1))
print(f"\nexported models/sound_head.tflite ({(MODELS_DIR/'sound_head.tflite').stat().st_size/1024:.0f} KB), labels.json, thresholds.json")
