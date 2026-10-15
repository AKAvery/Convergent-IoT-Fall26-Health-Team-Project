#!/usr/bin/env python3
"""
Build work/manifest.csv: one row per audio segment with path, label, split, source,
offset (s), duration (s; 0 = whole file).

Sources:
  - ESC-50 (data/ESC-50): mapped through config.TARGETS, rest -> "other"
  - FSDD   (data/FSDD):   all clips -> "speech"
  - DEMAND (data/DEMAND): real environments (kitchen, office, street...) -> "other"   [optional]
  - MUSAN  (data/musan):  noise + music -> "other"; speech -> "speech"              [optional]
  - my_clips/<label>/*.wav (optional): team recordings, split 80/20

Run: python3 prepare_data.py
"""
import csv, random
from collections import Counter
import soundfile as sf
from config import *

random.seed(0)
WORK_DIR.mkdir(exist_ok=True)
rows = []   # (path, label, split, source, offset, duration)

def add(path, label, split, source, offset=0.0, duration=0.0):
    rows.append((str(path), label, split, source, f"{offset:.2f}", f"{duration:.2f}"))

def chunk_file(path, label, split, source, cap):
    """Cut a long recording into BACKGROUND_CHUNK_SECONDS pieces (up to cap)."""
    try:
        info = sf.info(path)
    except Exception:
        return 0
    n = int(info.duration // BACKGROUND_CHUNK_SECONDS)
    picks = list(range(n)); random.shuffle(picks)
    for i in picks[:cap]:
        add(path, label, split, source, i * BACKGROUND_CHUNK_SECONDS, BACKGROUND_CHUNK_SECONDS)
    return min(n, cap)

# ---- ESC-50 ------------------------------------------------------------
with open(ESC50_DIR / "meta" / "esc50.csv") as f:
    esc = list(csv.DictReader(f))
other_by_fold = {}
for r in esc:
    fold = int(r["fold"])
    split = "test" if fold == TEST_FOLD else "train"
    label = TARGETS.get(r["category"])
    if label is None:
        other_by_fold.setdefault(fold, []).append((r["filename"], split))
        continue
    add(ESC50_DIR / "audio" / r["filename"], label, split, "esc50")
for fold, items in other_by_fold.items():
    random.shuffle(items)
    for fn, split in items[:OTHER_PER_FOLD]:
        add(ESC50_DIR / "audio" / fn, OTHER_LABEL, split, "esc50")

# ---- FSDD (speech) -----------------------------------------------------
fsdd = sorted(FSDD_DIR.glob("*.wav"))
random.shuffle(fsdd)
per_speaker = Counter()
for p in fsdd:
    speaker = p.stem.split("_")[1]
    if per_speaker[speaker] >= SPEECH_PER_SPEAKER:
        continue
    per_speaker[speaker] += 1
    add(p, SPEECH_LABEL, "test" if speaker in TEST_SPEAKERS else "train", "fsdd")

# ---- DEMAND (real environments -> other) ------------------------------
if DEMAND_DIR.exists():
    envs = sorted(d for d in DEMAND_DIR.iterdir() if d.is_dir())
    for i, env in enumerate(envs):
        ch = env / "ch01.wav"
        if not ch.exists():
            continue
        # hold out every 4th environment entirely so the test set has unseen rooms
        split = "test" if i % 4 == 3 else "train"
        chunk_file(ch, OTHER_LABEL, split, "demand", BACKGROUND_CHUNKS_PER_FOLDER)

# ---- MUSAN (noise, music -> other ; speech -> speech) ------------------
if MUSAN_DIR.exists():
    for sub, label in (("noise", OTHER_LABEL), ("music", OTHER_LABEL), ("speech", SPEECH_LABEL)):
        files = sorted((MUSAN_DIR / sub).rglob("*.wav"))
        random.shuffle(files)
        for j, p in enumerate(files[:BACKGROUND_CHUNKS_PER_FOLDER * 3]):
            split = "test" if j % 5 == 4 else "train"
            chunk_file(p, label, split, "musan", 2)

# ---- team recordings (optional) ---------------------------------------
if MY_CLIPS_DIR.exists():
    for d in sorted(MY_CLIPS_DIR.iterdir()):
        if not d.is_dir():
            continue
        clips = sorted(d.glob("*.wav"))
        random.shuffle(clips)
        n_test = max(1, len(clips) // 5) if len(clips) >= 5 else 0
        for i, p in enumerate(clips):
            add(p, d.name, "test" if i < n_test else "train", "mine")

with open(WORK_DIR / "manifest.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["path", "label", "split", "source", "offset", "duration"])
    w.writerows(rows)

print(f"{len(rows)} segments -> {WORK_DIR/'manifest.csv'}")
for split in ("train", "test"):
    c = Counter(r[1] for r in rows if r[2] == split)
    print(f"\n{split}:")
    for k, v in sorted(c.items()):
        print(f"  {k:12s} {v}")
src = Counter(r[3] for r in rows)
print("\nsources:", dict(src))
