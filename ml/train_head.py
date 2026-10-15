#!/usr/bin/env python3
"""
Train a small classifier head on YAMNet embeddings and export it for the Pi.

Outputs:
  models/sound_head.tflite   - the head (1024 -> n classes), ~0.5 MB
  models/labels.json         - class names in output order
  work/report.txt            - per-class precision/recall + confusion matrix

Run: python3 train_head.py
"""
import json
import numpy as np
import tensorflow as tf
from sklearn.metrics import classification_report, confusion_matrix
from config import *

d = np.load(WORK_DIR / "embeddings.npz")
X, y, split, clip_id = d["X"], d["y"], d["split"], d["clip_id"]
labels = sorted(set(y))
lab2i = {l: i for i, l in enumerate(labels)}
yi = np.array([lab2i[l] for l in y])

tr, te = split == "train", split == "test"
print(f"{len(labels)} classes: {labels}")
print(f"train windows {tr.sum()}, test windows {te.sum()}")

# class weights so "other"/"speech" (many windows) don't dominate
counts = np.bincount(yi[tr], minlength=len(labels))
cw = {i: float(len(yi[tr]) / (len(labels) * c)) for i, c in enumerate(counts)}

tf.random.set_seed(0)
model = tf.keras.Sequential([
    tf.keras.layers.Input(shape=(1024,)),
    tf.keras.layers.Dense(256, activation="relu"),
    tf.keras.layers.Dropout(0.4),
    tf.keras.layers.Dense(len(labels), activation="softmax"),
])
model.compile(optimizer=tf.keras.optimizers.Adam(1e-3),
              loss="sparse_categorical_crossentropy", metrics=["accuracy"])
model.fit(X[tr], yi[tr], validation_data=(X[te], yi[te]), epochs=40, batch_size=64,
          class_weight=cw, verbose=0,
          callbacks=[tf.keras.callbacks.EarlyStopping(patience=6, restore_best_weights=True)])

# ---- evaluate: per-window and per-clip (average the windows of each clip) ----
p_win = model.predict(X[te], verbose=0)
win_acc = (p_win.argmax(1) == yi[te]).mean()

clip_pred, clip_true = [], []
for cid in np.unique(clip_id[te]):
    m = te & (clip_id == cid)
    clip_pred.append(p_win[(clip_id[te] == cid)].mean(0).argmax())
    clip_true.append(yi[m][0])
clip_pred, clip_true = np.array(clip_pred), np.array(clip_true)
clip_acc = (clip_pred == clip_true).mean()

rep = classification_report(clip_true, clip_pred, target_names=labels, digits=3)
cm = confusion_matrix(clip_true, clip_pred)
out = [f"window accuracy: {win_acc:.3f}", f"clip accuracy:   {clip_acc:.3f}", "", rep, "",
       "confusion matrix (rows = true, cols = predicted)", "              " + " ".join(f"{l[:5]:>5s}" for l in labels)]
for l, row in zip(labels, cm):
    out.append(f"{l:12s}  " + " ".join(f"{v:5d}" for v in row))
report = "\n".join(out)
print(report)
(WORK_DIR / "report.txt").write_text(report)

# ---- export ---------------------------------------------------------------
conv = tf.lite.TFLiteConverter.from_keras_model(model)
conv.optimizations = [tf.lite.Optimize.DEFAULT]
(MODELS_DIR / "sound_head.tflite").write_bytes(conv.convert())
(MODELS_DIR / "labels.json").write_text(json.dumps(labels, indent=1))
print(f"\nexported models/sound_head.tflite ({(MODELS_DIR/'sound_head.tflite').stat().st_size/1024:.0f} KB) and models/labels.json")
