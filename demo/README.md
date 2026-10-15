# Live laptop demo

Runs the Sound Ring classifier on your computer's microphone and shows the ring in a
browser. No Pi needed. Same model files as the Pi (`../pi/`).

```bash
pip install sounddevice numpy tensorflow-cpu flask
cd demo
python3 live_demo.py
```

Open http://localhost:5050, allow mic access if macOS asks (System Settings → Privacy →
Microphone → Terminal/VS Code), then clap, talk, play a siren off YouTube on your phone, etc.

**What you'll see**
- Big label + confidence for the current sound; ring pulses in that sound's colour.
- Loudness meter.
- "Recent" list on the right.
- Top-3 guesses in small text (useful for seeing *why* it's unsure).

**Direction:** laptop mics are mono to apps, so the ring just pulses. If you plug in a
stereo interface or use a USB mic pair, it shows a left/right wedge from level
difference. True 360° direction needs the 4-mic hat.

**Options**
- `python3 live_demo.py --list` shows input devices; `--device N` picks one.
- Edit `MIN_CONFIDENCE` / `LOUDNESS_GATE_DB` at the top if it's too twitchy or too quiet.

**Playing test sounds:** search YouTube on your phone for "dog barking sound effect",
"smoke alarm sound", "doorbell sound", "baby crying". Hold the phone a few feet from the
laptop. Speech works just by talking.
