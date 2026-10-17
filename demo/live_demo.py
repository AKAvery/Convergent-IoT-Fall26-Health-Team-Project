#!/usr/bin/env python3
"""
Live laptop demo: listens on your computer's microphone, classifies sounds with the
same model the Pi uses, and shows a Fortnite-style ring in your browser.

    pip install -r requirements.txt
    python3 live_demo.py
    -> open http://localhost:5050

Options
    --list            show input devices        --device N      pick one
    --preset NAME     which sounds are alerts (all, safety, babies, privacy, household)
    --gain DB         digital input gain, e.g. --gain 12 if your mic is quiet
    --baseline        run the pre-harness pipeline (0.25 s hop, -50 dB 1 s RMS gate) for comparison
    --wav PATH        play a WAV file through the pipeline in real time instead of the mic

The detection logic lives in detector.py and is shared with ml/eval_pipeline.py, so what you
see here is exactly what the harness measures.

Laptop mics are (usually) mono, so direction is estimated only when a stereo input
exists (left/right from level difference). Otherwise the whole ring pulses.
"""
import sys, json, math, time, threading
from pathlib import Path
import numpy as np
from flask import Flask, jsonify, Response, send_from_directory, request

from detector import Detector, DetectorParams, PRESETS, SAMPLE_RATE, json_safe

RENDER_DIR = Path(__file__).resolve().parent.parent / "docs" / "rendering"   # 3D glasses concept page
HISTORY = 12
MIC_WARN_SECONDS = 2.0
MIC_WARN_DB = -40

COLORS = {
    "siren": "#ff2d2d", "alarm": "#ff2d2d", "car_horn": "#ff6a00", "glass_break": "#b400ff",
    "dog": "#ffa000", "cat": "#ffa000", "baby_cry": "#ff64c8", "knock": "#00c8ff",
    "clap": "#ffffff", "footsteps": "#ffff00", "speech": "#2ecc71", "appliance": "#0050ff",
    "other": "#555555",
}

# ---------------------------------------------------------------- state --
state = {"label": None, "conf": 0.0, "db": -100.0, "angle": None, "top3": [], "hits": [], "alerts": [],
         "history": [], "ts": 0, "gated": True, "preset": "all", "gate_db": None, "peak_db": -100.0,
         "clip_frac": 0.0, "level_db": -100.0}
lock = threading.Lock()
detector = None   # set in main before the audio loop starts


def push_state(st, angle):
    """Copy one Detector.process() result into the shared state (plus direction + history)."""
    with lock:
        state.update(json_safe(st))
        state["angle"] = angle
        state["ts"] = time.time()
        if st["label"] is not None:
            h = state["history"]
            if not h or h[0]["label"] != st["label"] or time.time() - h[0]["t"] > 2:
                h.insert(0, {"label": st["label"], "conf": round(st["conf"], 2), "db": round(st["db"]), "t": time.time()})
                del h[HISTORY:]


# ---------------------------------------------------------------- audio --
def audio_loop(device=None):
    import sounddevice as sd
    info = sd.query_devices(device, "input")
    channels = min(2, int(info["max_input_channels"]))
    print(f"mic: {info['name']}  channels used: {channels}")
    frames = detector.hop
    warn_peak, warn_frames, warned = 0.0, 0, False
    with sd.InputStream(device=device, channels=channels, samplerate=SAMPLE_RATE,
                        dtype="float32", blocksize=frames) as stream:
        while True:
            block, _ = stream.read(frames)
            mono = block.mean(axis=1)
            if not warned:
                warn_peak = max(warn_peak, float(np.abs(block).max())); warn_frames += 1
                if warn_frames * frames >= MIC_WARN_SECONDS * SAMPLE_RATE:
                    warned = True
                    peak_db = 20 * math.log10(warn_peak + 1e-9)
                    if peak_db < MIC_WARN_DB:
                        print(f"WARNING: mic input peaked at {peak_db:.0f} dBFS in the first {MIC_WARN_SECONDS:.0f} s. "
                              f"Raise the input volume (System Settings -> Sound -> Input) or use --gain.")
            angle = None
            if channels == 2:
                l = np.sqrt(np.mean(block[:, 0] ** 2)) + 1e-9
                r = np.sqrt(np.mean(block[:, 1] ** 2)) + 1e-9
                bal = max(-1.0, min(1.0, 20 * math.log10(r / l) / 6.0))   # ±6 dB -> full left/right
                angle = 90 * bal                                           # -90 = left, +90 = right
            push_state(detector.process(mono), angle)


def load_wav_16k(path):
    """Mono float32 at 16 kHz. Uses soundfile+resampy if installed, else stdlib wave + linear resample."""
    try:
        import soundfile as sf, resampy
        y, sr = sf.read(path, dtype="float32", always_2d=True)
        y = y.mean(axis=1)
        return y if sr == SAMPLE_RATE else resampy.resample(y, sr, SAMPLE_RATE)
    except ImportError:
        import wave
        with wave.open(path, "rb") as w:
            sr, n, width, ch = w.getframerate(), w.getnframes(), w.getsampwidth(), w.getnchannels()
            raw = w.readframes(n)
        if width != 2:
            sys.exit("only 16-bit PCM WAV supported without soundfile installed")
        y = np.frombuffer(raw, dtype=np.int16).astype(np.float32).reshape(-1, ch).mean(axis=1) / 32768
        if sr != SAMPLE_RATE:
            t_new = np.arange(0, len(y) / sr, 1 / SAMPLE_RATE)
            y = np.interp(t_new, np.arange(len(y)) / sr, y).astype(np.float32)   # crude, fine for a manual check
        return y


def wav_loop(path):
    """Feed a file through the pipeline at real-time speed (2 s of silence before and after), then loop."""
    y = load_wav_16k(path)
    pad = np.zeros(2 * SAMPLE_RATE, dtype=np.float32)
    stream = np.concatenate([pad, y, pad])
    hop = detector.hop
    print(f"playing {path} ({len(y)/SAMPLE_RATE:.1f} s, peak {20*math.log10(np.abs(y).max()+1e-9):.0f} dBFS) on a loop")
    while True:
        detector.reset()
        for i in range(0, len(stream) - hop + 1, hop):
            t0 = time.time()
            push_state(detector.process(stream[i:i + hop]), None)
            time.sleep(max(0.0, detector.p.hop_s - (time.time() - t0)))


# ---------------------------------------------------------------- web --
app = Flask(__name__)

@app.route("/state")
def get_state():
    with lock:
        return jsonify(state)

@app.route("/preset/<name>", methods=["POST"])
def set_preset(name):
    if name not in PRESETS:
        return jsonify({"error": f"unknown preset {name}", "presets": sorted(PRESETS)}), 400
    with lock:
        detector.set_preset(name)
        state["preset"] = name
    return jsonify({"preset": name})

@app.route("/rendering")
def rendering():
    """Interactive 3D concept of the glasses frame (docs/rendering/); it polls /state to show live sounds."""
    return send_from_directory(RENDER_DIR, "index.html", max_age=0)

@app.route("/rendering/<path:filename>")
def rendering_asset(filename):
    """Extra files next to the page, e.g. a CAD export loaded with /rendering?model=frame.glb."""
    return send_from_directory(RENDER_DIR, filename, max_age=0)

PAGE = """<!doctype html><html><head><meta charset="utf-8"><title>Sound Ring live</title>
<style>
body{margin:0;background:#0b0f14;color:#eee;font-family:-apple-system,Helvetica,Arial,sans-serif;display:flex;height:100vh}
#left{flex:1;display:flex;flex-direction:column;align-items:center;justify-content:center}
#right{width:300px;padding:24px;border-left:1px solid #222;overflow:auto}
h1{font-weight:600;font-size:18px;letter-spacing:.08em;color:#9aa;margin:0 0 16px}
#label{font-size:40px;font-weight:700;margin-top:18px;min-height:48px;text-transform:uppercase;letter-spacing:.04em}
#conf{color:#9aa;font-size:14px;margin-top:4px}
.row{display:flex;justify-content:space-between;padding:8px 0;border-bottom:1px solid #1c232b;font-size:14px}
.dot{display:inline-block;width:10px;height:10px;border-radius:50%;margin-right:8px;vertical-align:middle}
#meter{width:240px;height:6px;background:#1c232b;border-radius:3px;margin-top:14px;overflow:hidden}
#meterfill{height:100%;width:0;background:#2ecc71;transition:width .15s}
small{color:#667}
#top3{margin-top:10px;font-size:12px;color:#889}
#also{margin-top:8px;font-size:14px;color:#aab;min-height:18px}
#clip{color:#ff2d2d;font-size:12px;min-height:16px;margin-top:6px}
select{background:#141a21;color:#eee;border:1px solid #2a333d;padding:6px 8px;font-size:14px;border-radius:4px;width:100%;margin-bottom:20px}
label.sm{display:block;font-size:11px;letter-spacing:.08em;text-transform:uppercase;color:#667;margin-bottom:6px}
</style></head><body>
<div id="left">
  <svg id="ring" width="360" height="360" viewBox="-100 -100 200 200">
    <circle r="90" fill="none" stroke="#1c232b" stroke-width="2"/>
    <circle r="60" fill="none" stroke="#1c232b" stroke-width="1"/>
    <g id="ticks" stroke="#2a333d"></g>
    <path id="wedge" d="" fill="#fff" opacity="0"/>
    <circle id="pulse" r="90" fill="none" stroke="#fff" stroke-width="6" opacity="0"/>
    <path d="M0 -10 L8 8 L0 3 L-8 8 Z" fill="#eee"/>
  </svg>
  <div id="label">listening…</div>
  <div id="conf"></div>
  <div id="meter"><div id="meterfill"></div></div>
  <div id="clip"></div>
  <div id="also"></div>
  <div id="top3"></div>
  <small style="margin-top:20px">front = up · laptop mic gives left/right only</small>
</div>
<div id="right">
  <label class="sm" for="preset">Alerts</label>
  <select id="preset">%PRESET_OPTIONS%</select>
  <h1>RECENT</h1><div id="hist"></div>
  <p style="margin-top:24px"><a href="/rendering" style="color:#9aa;font-size:12px;letter-spacing:.08em;text-transform:uppercase;text-decoration:none">3D glasses concept →</a></p>
</div>
<script>
const C=%COLORS%;
const ticks=document.getElementById('ticks');
for(let i=0;i<12;i++){const a=i*30*Math.PI/180;const l=document.createElementNS('http://www.w3.org/2000/svg','line');
 l.setAttribute('x1',Math.sin(a)*84);l.setAttribute('y1',-Math.cos(a)*84);l.setAttribute('x2',Math.sin(a)*90);l.setAttribute('y2',-Math.cos(a)*90);ticks.appendChild(l);}
function wedge(angle,w){const a0=(angle-w)*Math.PI/180,a1=(angle+w)*Math.PI/180,R=90;
 return `M0 0 L${Math.sin(a0)*R} ${-Math.cos(a0)*R} A${R} ${R} 0 0 1 ${Math.sin(a1)*R} ${-Math.cos(a1)*R} Z`;}
const sel=document.getElementById('preset');
sel.addEventListener('change',()=>fetch('/preset/'+sel.value,{method:'POST'}));
let presetSynced=false;
async function tick(){
 try{const s=await (await fetch('/state')).json();
  if(!presetSynced&&s.preset){sel.value=s.preset;presetSynced=true;}
  const col=C[s.label]||'#fff';
  document.getElementById('meterfill').style.width=Math.max(0,Math.min(100,(s.db+60)*100/60))+'%';
  document.getElementById('clip').textContent=(s.clip_frac>0.01)?'mic clipping — lower the volume':'';
  const wd=document.getElementById('wedge'),pu=document.getElementById('pulse');
  if(s.label){
   document.getElementById('label').textContent=s.label.replace('_',' ');document.getElementById('label').style.color=col;
   document.getElementById('conf').textContent=Math.round(s.conf*100)+'% confident · '+Math.round(s.db)+' dB';
   if(s.angle!==null){wd.setAttribute('d',wedge(s.angle,25));wd.setAttribute('fill',col);wd.setAttribute('opacity',.8);pu.setAttribute('opacity',0);}
   else{wd.setAttribute('opacity',0);pu.setAttribute('stroke',col);pu.setAttribute('opacity',.9);}
  }else{document.getElementById('label').textContent=s.gated?'quiet':'…';document.getElementById('label').style.color='#556';
   document.getElementById('conf').textContent=s.gated?('below '+Math.round(s.gate_db)+' dB gate'):'';wd.setAttribute('opacity',0);pu.setAttribute('opacity',0);}
  document.getElementById('also').innerHTML=(s.hits||[]).filter(h=>h.label!==s.label).map(h=>`<span class="dot" style="background:${C[h.label]||'#fff'}"></span>${h.label.replace('_',' ')} ${Math.round(h.conf*100)}%`).join('&nbsp;&nbsp;&nbsp;');
  document.getElementById('top3').textContent=(s.top3||[]).map(t=>t[0]+' '+Math.round(t[1]*100)+'%').join('   ');
  document.getElementById('hist').innerHTML=(s.history||[]).map(h=>`<div class="row"><span><span class="dot" style="background:${C[h.label]||'#fff'}"></span>${h.label.replace('_',' ')}</span><span>${Math.round(h.conf*100)}%</span></div>`).join('');
 }catch(e){}
 setTimeout(tick,150);}
tick();
</script></body></html>"""

@app.route("/")
def index():
    opts = "".join(f'<option value="{p}">{p}</option>' for p in PRESETS)
    return Response(PAGE.replace("%COLORS%", json.dumps(COLORS)).replace("%PRESET_OPTIONS%", opts), mimetype="text/html")


def arg(flag, default=None, cast=str):
    if flag in sys.argv:
        return cast(sys.argv[sys.argv.index(flag) + 1])
    return default


if __name__ == "__main__":
    if "--list" in sys.argv:
        import sounddevice as sd
        print(sd.query_devices()); sys.exit()
    params = DetectorParams.baseline() if "--baseline" in sys.argv else DetectorParams.default()
    params.input_gain_db = arg("--gain", 0.0, float)
    detector = Detector(params, preset=arg("--preset", "all"))
    state["preset"] = detector.preset; state["gate_db"] = params.gate_db
    print(f"pipeline: {'baseline' if '--baseline' in sys.argv else 'default'}  ({params.describe()})")
    # Flask in the background; audio + model on the MAIN thread (macOS CoreAudio and
    # the mic-permission prompt are much happier that way).
    import logging; logging.getLogger("werkzeug").setLevel(logging.ERROR)
    threading.Thread(target=lambda: app.run(host="127.0.0.1", port=5050, debug=False, use_reloader=False),
                     daemon=True).start()
    print("open http://localhost:5050")
    try:
        wav = arg("--wav")
        wav_loop(wav) if wav else audio_loop(arg("--device", None, int))
    except KeyboardInterrupt:
        print("\nbye")
        import os; os._exit(0)   # skip TensorFlow's teardown, which segfaults on macOS
