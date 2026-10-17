# Live laptop demo

Runs the Sound Ring classifier on your computer's microphone and shows the ring in a
browser. No Pi needed. Same model files as the Pi (`../pi/`).

```bash
git clone https://github.com/AKAvery/Convergent-IoT-Fall26-Health-Team-Project
cd Convergent-IoT-Fall26-Health-Team-Project/demo
python3 -m venv .venv
source .venv/bin/activate        # Windows: .venv\Scripts\activate
pip install -r requirements.txt  # tensorflow is ~250 MB, takes a minute
python3 live_demo.py
```

Needs Python 3.10–3.12 (`python3 --version`). On a Mac, `brew install python@3.12` if
you only have the system 3.9. The model files are committed, nothing else to download.

Open http://localhost:5050, allow mic access if macOS asks (System Settings → Privacy →
Microphone → Terminal/VS Code), then clap, talk, play a siren off YouTube on your phone, etc.

**What you'll see**
- Big label + confidence for the current sound; ring pulses in that sound's colour.
- Loudness meter.
- "Recent" list on the right.
- Top-3 guesses in small text (useful for seeing *why* it's unsure).
- http://localhost:5050/rendering: a rotatable 3D concept of the glasses frame (4 mics, bridge
  camera, ESP32-S3 and battery in the temples; the Crystal finish shows the electronics and
  wiring). It polls the same `/state` feed and draws each detected sound as a glowing arc on the
  floor at its bearing. The page is `docs/rendering/index.html`; it also opens on its own.

**Direction:** laptop mics are mono to apps, so the ring just pulses. If you plug in a
stereo interface or use a USB mic pair, it shows a left/right wedge from level
difference. True 360° direction needs the 4-mic hat.

**Options**
- `python3 live_demo.py --list` shows input devices; `--device N` picks one.
- `--preset safety|babies|privacy|household|all` chooses which sounds become the big alert
  (also a dropdown on the page). Everything that fires still shows in the "also" row.
- `--gain 12` adds digital input gain if the mic is quiet. The demo warns at startup when the
  first 2 s of mic input peak below -40 dBFS; the fix is System Settings → Sound → Input level.
- `--baseline` runs the pipeline as it was before `detector.py` (0.25 s hop, -50 dB gate on 1 s
  RMS) for side-by-side comparisons.
- `--wav path.wav` plays a file through the pipeline on a loop instead of using the mic.
- Tunables (gate, hop, persistence, veto) live in `detector.py` → `DetectorParams`. Don't guess:
  change them and run `python3 ../ml/eval_pipeline.py --compare`, which scores the exact same
  code on the test clips and fails if any class regresses. See `../ml/README.md`.

**Playing test sounds:** search YouTube on your phone for "dog barking sound effect",
"smoke alarm sound", "siren", "baby crying", "glass breaking". Hold the phone a few feet from the
laptop. Speech works just by talking. Doorbell, phone ring and microwave beep are **not** trained
classes yet; they can only come out as a wrong label or nothing (see `ml/README.md` → add your
own sounds). If the page shows "mic clipping", turn the speaker down: a clipped recording is a
different sound to the model.
