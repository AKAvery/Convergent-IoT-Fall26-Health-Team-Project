#!/usr/bin/env python3
"""
Record training clips from your laptop mic into data/my_clips/<label>/.

    python3 record_clips.py clap            # record 'clap' clips, 2 s each
    python3 record_clips.py doorbell 3      # 3 s clips

Press Enter to record each clip, 'q' then Enter to stop. Aim for 20-40 per label,
from different distances / spots in the room. Then re-run:
    python3 prepare_data.py && python3 extract_embeddings.py && python3 train_head.py
    cp models/sound_head.tflite models/labels.json ../pi/
"""
import sys, time
import numpy as np
import sounddevice as sd
import soundfile as sf
from config import MY_CLIPS_DIR, SAMPLE_RATE

label = sys.argv[1] if len(sys.argv) > 1 else None
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0
if not label:
    print(__doc__); sys.exit(1)

out = MY_CLIPS_DIR / label
out.mkdir(parents=True, exist_ok=True)
n = len(list(out.glob("*.wav")))
print(f"recording '{label}' clips ({secs:.0f}s each) into {out}  — {n} already there")
print("Enter = record, q = quit")
while True:
    if input("> ").strip().lower() == "q":
        break
    print("  recording…", end="", flush=True)
    audio = sd.rec(int(secs * SAMPLE_RATE), samplerate=SAMPLE_RATE, channels=1, dtype="float32", blocking=True)
    peak = float(np.abs(audio).max())
    if peak < 0.01:
        print(" too quiet, skipped (peak %.3f)" % peak); continue
    n += 1
    path = out / f"{label}_{n:03d}_{int(time.time())}.wav"
    sf.write(path, audio, SAMPLE_RATE)
    print(f" saved {path.name}  (peak {peak:.2f})")
print(f"{n} clips in {out}")
