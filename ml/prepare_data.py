#!/usr/bin/env python3
"""
Build work/manifest.csv: one row per audio clip with path, label, split.

Sources:
  - ESC-50 (data/ESC-50): mapped through config.TARGETS, rest -> "other"
  - FSDD   (data/FSDD):   all clips -> "speech"
  - my_clips/<label>/*.wav (optional): team recordings, split 80/20

Run: python3 prepare_data.py
"""
import csv, random
from collections import Counter
from config import *

random.seed(0)
WORK_DIR.mkdir(exist_ok=True)
rows = []

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
    rows.append((str(ESC50_DIR / "audio" / r["filename"]), label, split, "esc50"))
for fold, items in other_by_fold.items():
    random.shuffle(items)
    for fn, split in items[:OTHER_PER_FOLD]:
        rows.append((str(ESC50_DIR / "audio" / fn), OTHER_LABEL, split, "esc50"))

# ---- FSDD (speech) -----------------------------------------------------
fsdd = sorted(FSDD_DIR.glob("*.wav"))
random.shuffle(fsdd)
per_speaker = Counter()
for p in fsdd:
    speaker = p.stem.split("_")[1]
    if per_speaker[speaker] >= SPEECH_PER_SPEAKER:
        continue
    per_speaker[speaker] += 1
    split = "test" if speaker in TEST_SPEAKERS else "train"
    rows.append((str(p), SPEECH_LABEL, split, "fsdd"))

# ---- team recordings (optional) ---------------------------------------
if MY_CLIPS_DIR.exists():
    for d in sorted(MY_CLIPS_DIR.iterdir()):
        if not d.is_dir():
            continue
        clips = sorted(d.glob("*.wav"))
        random.shuffle(clips)
        n_test = max(1, len(clips) // 5)
        for i, p in enumerate(clips):
            rows.append((str(p), d.name, "test" if i < n_test else "train", "mine"))

with open(WORK_DIR / "manifest.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["path", "label", "split", "source"])
    w.writerows(rows)

print(f"{len(rows)} clips -> {WORK_DIR/'manifest.csv'}")
for split in ("train", "test"):
    c = Counter(r[1] for r in rows if r[2] == split)
    print(f"\n{split}:")
    for k, v in sorted(c.items()):
        print(f"  {k:12s} {v}")
