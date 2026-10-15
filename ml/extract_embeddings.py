#!/usr/bin/env python3
"""
Run every segment in work/manifest.csv through YAMNet (TFLite embedding model)
and save one 1024-d embedding per 0.975 s window to work/embeddings.npz.

Training-split augmentation (so the model copes with real rooms):
  - noise mixing: each target clip also gets AUG_COPIES noisy versions, mixed with a
    random background ("other") segment at a random SNR and gain
  - single-hit isolation: for TRANSIENT_LABELS (clap, knock) we cut out individual
    hits by onset detection and paste one hit onto background, so a lone clap is
    learned, not only applause

Run: python3 extract_embeddings.py
"""
import csv, time, random
import numpy as np
import soundfile as sf
import resampy
import tensorflow as tf
from config import *

random.seed(0); np.random.seed(0)

# ------------------------------------------------------------ audio io --
def load_mono_16k(path, offset=0.0, duration=0.0):
    info = sf.info(path)
    start = int(offset * info.samplerate)
    frames = int(duration * info.samplerate) if duration > 0 else -1
    y, sr = sf.read(path, dtype="float32", always_2d=True, start=start, frames=frames)
    y = y.mean(axis=1)
    if sr != SAMPLE_RATE:
        y = resampy.resample(y, sr, SAMPLE_RATE)
    return y

def normalise(y):
    peak = np.abs(y).max()
    return y / peak * 0.5 if peak > 0 else y

def windows(y):
    if len(y) < WINDOW:
        y = np.pad(y, (0, WINDOW - len(y)))
    for start in range(0, len(y) - WINDOW + 1, HOP):
        yield y[start:start + WINDOW]

# -------------------------------------------------------- augmentation --
def rms(x):
    return float(np.sqrt(np.mean(x ** 2)) + 1e-9)

def random_crop(y, n):
    if len(y) <= n:
        return np.pad(y, (0, n - len(y)))
    s = random.randrange(0, len(y) - n + 1)
    return y[s:s + n]

def mix_with_noise(sig, noise, snr_db):
    noise = random_crop(noise, len(sig))
    g = rms(sig) / (rms(noise) * 10 ** (snr_db / 20))
    out = sig + noise * g
    out *= 10 ** (random.uniform(*AUG_GAIN_DB) / 20)
    return normalise(out)

def isolate_hits(y, max_hits=6, hit_len=int(0.35 * SAMPLE_RATE)):
    """Crude onset detector: return up to max_hits short chunks starting at energy spikes."""
    frame = 400
    env = np.array([rms(y[i:i + frame]) for i in range(0, len(y) - frame, frame)])
    if len(env) < 3:
        return []
    thr = env.mean() + 2.5 * env.std()
    hits, last = [], -10
    for i in range(1, len(env)):
        if env[i] > thr and env[i] > env[i - 1] * 2 and i - last > int(0.3 * SAMPLE_RATE / frame):
            s = max(0, i * frame - 400)
            hits.append(y[s:s + hit_len]); last = i
            if len(hits) >= max_hits:
                break
    return [h for h in hits if len(h) > frame * 4]

def paste_hit(hit, bg, snr_db):
    bg = random_crop(bg, WINDOW)
    bg = bg * (rms(hit) / (rms(bg) * 10 ** (snr_db / 20)))
    out = bg.copy()
    pos = random.randrange(0, WINDOW - len(hit))
    out[pos:pos + len(hit)] += hit
    return normalise(out)

# ------------------------------------------------------------------ main --
def main():
    it = tf.lite.Interpreter(model_path=str(YAMNET_EMBED_TFLITE), num_threads=4)
    it.allocate_tensors()
    in_idx = it.get_input_details()[0]["index"]
    out_idx = it.get_output_details()[0]["index"]

    def embed(w):
        it.set_tensor(in_idx, w[np.newaxis, :].astype(np.float32))
        it.invoke()
        return it.get_tensor(out_idx)[0].copy()

    with open(WORK_DIR / "manifest.csv") as f:
        rows = list(csv.DictReader(f))
    for r in rows:
        r["offset"] = float(r.get("offset", 0) or 0); r["duration"] = float(r.get("duration", 0) or 0)

    # background pool for augmentation: train-split "other" segments
    bg_rows = [r for r in rows if r["label"] == OTHER_LABEL and r["split"] == "train"]
    print(f"{len(rows)} segments, {len(bg_rows)} background segments for augmentation")
    bg_cache = {}
    def random_bg():
        r = random.choice(bg_rows)
        key = (r["path"], r["offset"])
        if key not in bg_cache:
            bg_cache[key] = load_mono_16k(r["path"], r["offset"], r["duration"])
        return bg_cache[key]

    labels = sorted(set(r["label"] for r in rows))
    lab2i = {l: i for i, l in enumerate(labels)}
    X, Y, split, clip_id, aug = [], [], [], [], []
    def push(w, label_set, sp, cid, is_aug):
        t = np.zeros(len(labels), dtype=np.float32)
        for l in label_set: t[lab2i[l]] = 1.0
        X.append(embed(w)); Y.append(t); split.append(sp); clip_id.append(cid); aug.append(is_aug)
    target_rows = [(i, r) for i, r in enumerate(rows) if r["label"] not in (OTHER_LABEL,) and r["split"] == "train"]
    audio_cache = {}
    def load_cached(i, r):
        if i not in audio_cache:
            audio_cache[i] = load_mono_16k(r["path"], r["offset"], r["duration"])
        return audio_cache[i]

    t0 = time.time()
    for i, r in enumerate(rows):
        audio = load_mono_16k(r["path"], r["offset"], r["duration"])
        label, sp = r["label"], r["split"]
        for w in windows(normalise(audio)):
            push(w, {label}, sp, i, False)

        if sp == "train" and label != OTHER_LABEL and bg_rows:
            for _ in range(AUG_COPIES):
                noisy = mix_with_noise(audio, random_bg(), random.uniform(*AUG_SNR_DB))
                push(random_crop(noisy, WINDOW), {label}, sp, i, True)
            if label in TRANSIENT_LABELS:
                hits = isolate_hits(audio)
                for _ in range(TRANSIENT_COPIES if hits else 0):
                    push(paste_hit(random.choice(hits), random_bg(), random.uniform(5, 25)), {label}, sp, i, True)
            # overlap: mix with a DIFFERENT target sound, both labels on
            for _ in range(OVERLAP_COPIES):
                j, r2 = random.choice(target_rows)
                if r2["label"] == label:
                    continue
                a = random_crop(normalise(audio), WINDOW)
                b = random_crop(normalise(load_cached(j, r2)), WINDOW)
                ratio = random.uniform(*OVERLAP_RATIO_DB)
                mixed = normalise(a + b * 10 ** (ratio / 20))
                push(mixed, {label, r2["label"]}, sp, i, True)

        if (i + 1) % 200 == 0:
            print(f"{i+1}/{len(rows)} segments, {len(X)} windows, {time.time()-t0:.0f}s", flush=True)

    np.savez_compressed(WORK_DIR / "embeddings.npz",
                        X=np.array(X, dtype=np.float32), Y=np.array(Y, dtype=np.float32), labels=np.array(labels),
                        split=np.array(split), clip_id=np.array(clip_id), aug=np.array(aug))
    print(f"saved {len(X)} embeddings ({int(np.sum(aug))} augmented) from {len(rows)} segments in {time.time()-t0:.0f}s")

if __name__ == "__main__":
    main()
