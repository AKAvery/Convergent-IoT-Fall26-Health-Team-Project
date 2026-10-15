#!/usr/bin/env python3
"""
Run every clip in work/manifest.csv through YAMNet (TFLite embedding model)
and save one 1024-d embedding per 0.975 s window to work/embeddings.npz.

Run: python3 extract_embeddings.py
"""
import csv, sys, time
import numpy as np
import soundfile as sf
import resampy
import tensorflow as tf
from config import *

def load_mono_16k(path):
    y, sr = sf.read(path, dtype="float32", always_2d=True)
    y = y.mean(axis=1)
    if sr != SAMPLE_RATE:
        y = resampy.resample(y, sr, SAMPLE_RATE)
    # normalise peak so quiet FSDD clips and loud ESC clips look alike to the model
    peak = np.abs(y).max()
    if peak > 0:
        y = y / peak * 0.5
    return y

def windows(y):
    if len(y) < WINDOW:
        y = np.pad(y, (0, WINDOW - len(y)))
    for start in range(0, len(y) - WINDOW + 1, HOP):
        yield y[start:start + WINDOW]

def main():
    it = tf.lite.Interpreter(model_path=str(YAMNET_EMBED_TFLITE), num_threads=4)
    it.allocate_tensors()
    in_idx = it.get_input_details()[0]["index"]
    out_idx = it.get_output_details()[0]["index"]

    with open(WORK_DIR / "manifest.csv") as f:
        rows = list(csv.DictReader(f))

    X, y, split, clip_id = [], [], [], []
    t0 = time.time()
    for i, r in enumerate(rows):
        audio = load_mono_16k(r["path"])
        for w in windows(audio):
            it.set_tensor(in_idx, w[np.newaxis, :].astype(np.float32))
            it.invoke()
            X.append(it.get_tensor(out_idx)[0].copy())
            y.append(r["label"]); split.append(r["split"]); clip_id.append(i)
        if (i + 1) % 200 == 0:
            print(f"{i+1}/{len(rows)} clips, {len(X)} windows, {time.time()-t0:.0f}s", flush=True)

    np.savez_compressed(WORK_DIR / "embeddings.npz",
                        X=np.array(X, dtype=np.float32), y=np.array(y),
                        split=np.array(split), clip_id=np.array(clip_id))
    print(f"saved {len(X)} embeddings from {len(rows)} clips in {time.time()-t0:.0f}s")

if __name__ == "__main__":
    main()
