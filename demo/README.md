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
- Edit `MIN_CONFIDENCE` / `LOUDNESS_GATE_DB` at the top if it's too twitchy or too quiet.

**Playing test sounds:** search YouTube on your phone for "dog barking sound effect",
"smoke alarm sound", "doorbell sound", "baby crying". Hold the phone a few feet from the
laptop. Speech works just by talking.
