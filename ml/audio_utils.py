"""Audio loading and slicing helpers shared by training (extract_embeddings.py) and the
live-pipeline evaluation harness (eval_pipeline.py). No TensorFlow import here on purpose."""
import random
import numpy as np
import soundfile as sf
import resampy
from config import SAMPLE_RATE, WINDOW, HOP


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


def rms(x):
    return float(np.sqrt(np.mean(x ** 2)) + 1e-9)


def random_crop(y, n):
    if len(y) <= n:
        return np.pad(y, (0, n - len(y)))
    s = random.randrange(0, len(y) - n + 1)
    return y[s:s + n]
