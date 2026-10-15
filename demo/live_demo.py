#!/usr/bin/env python3
"""
Live laptop demo: listens on your computer's microphone, classifies sounds with the
same model the Pi uses, and shows a Fortnite-style ring in your browser.

    pip install sounddevice numpy tensorflow-cpu flask
    python3 live_demo.py
    -> open http://localhost:5050

Laptop mics are (usually) mono, so direction is estimated only when a stereo input
exists (left/right from level difference). Otherwise the whole ring pulses.
"""
import sys, json, math, time, threading, collections
from pathlib import Path
import numpy as np
import sounddevice as sd
from flask import Flask, jsonify, Response

try:
    import tflite_runtime.interpreter as tflite
except ImportError:
    import tensorflow.lite as tflite

PI_DIR = Path(__file__).resolve().parent.parent / "pi"
SAMPLE_RATE = 16000
WINDOW = 15600
BUFFER_SECONDS = 1.0
UPDATE_SECONDS = 0.25
LOUDNESS_GATE_DB = -50
MIN_CONFIDENCE = 0.5
HISTORY = 12

COLORS = {
    "siren": "#ff2d2d", "alarm": "#ff2d2d", "car_horn": "#ff6a00", "glass_break": "#b400ff",
    "dog": "#ffa000", "cat": "#ffa000", "baby_cry": "#ff64c8", "knock": "#00c8ff",
    "clap": "#ffffff", "footsteps": "#ffff00", "speech": "#2ecc71", "appliance": "#0050ff",
    "other": "#555555",
}

# ---------------------------------------------------------------- model --
class Classifier:
    def __init__(self):
        self.embed = tflite.Interpreter(model_path=str(PI_DIR / "yamnet_embedding_metadata.tflite"), num_threads=4)
        self.embed.allocate_tensors()
        self.e_in = self.embed.get_input_details()[0]["index"]
        self.e_out = self.embed.get_output_details()[0]["index"]
        self.head = tflite.Interpreter(model_path=str(PI_DIR / "sound_head.tflite"))
        self.head.allocate_tensors()
        self.h_in = self.head.get_input_details()[0]["index"]
        self.h_out = self.head.get_output_details()[0]["index"]
        self.names = json.loads((PI_DIR / "labels.json").read_text())

    def classify(self, mono):
        mono = mono.astype(np.float32)
        peak = np.abs(mono).max()
        if peak > 0:
            mono = mono / peak * 0.5
        if len(mono) < WINDOW:
            mono = np.pad(mono, (0, WINDOW - len(mono)))
        w = mono[-WINDOW:]
        self.embed.set_tensor(self.e_in, w[np.newaxis, :]); self.embed.invoke()
        emb = self.embed.get_tensor(self.e_out)
        self.head.set_tensor(self.h_in, emb); self.head.invoke()
        p = self.head.get_tensor(self.h_out)[0]
        order = np.argsort(p)[::-1]
        return [(self.names[i], float(p[i])) for i in order[:3]]

# ---------------------------------------------------------------- audio --
state = {"label": None, "conf": 0.0, "db": -100.0, "angle": None, "top3": [], "history": [], "ts": 0}
lock = threading.Lock()

def audio_loop(device=None):
    net = Classifier()
    info = sd.query_devices(device, "input")
    channels = min(2, int(info["max_input_channels"]))
    print(f"mic: {info['name']}  channels used: {channels}")
    buf = collections.deque(maxlen=int(BUFFER_SECONDS * SAMPLE_RATE))
    frames = int(UPDATE_SECONDS * SAMPLE_RATE)
    with sd.InputStream(device=device, channels=channels, samplerate=SAMPLE_RATE,
                        dtype="float32", blocksize=frames) as stream:
        while True:
            block, _ = stream.read(frames)
            buf.extend(block)
            if len(buf) < buf.maxlen:
                continue
            x = np.array(buf)
            mono = x.mean(axis=1)
            rms = np.sqrt(np.mean(mono ** 2))
            db = 20 * math.log10(rms + 1e-9)
            angle = None
            if channels == 2:
                l = np.sqrt(np.mean(x[-frames:, 0] ** 2)) + 1e-9
                r = np.sqrt(np.mean(x[-frames:, 1] ** 2)) + 1e-9
                bal = max(-1.0, min(1.0, 20 * math.log10(r / l) / 6.0))   # ±6 dB -> full left/right
                angle = 90 * bal                                           # -90 = left, +90 = right
            with lock:
                state["db"] = db
                state["angle"] = angle
                state["ts"] = time.time()
                if db < LOUDNESS_GATE_DB:
                    state["label"] = None; state["conf"] = 0.0; state["top3"] = []
                    continue
                top = net.classify(mono)
                state["top3"] = top
                name, conf = top[0]
                if name == "other" or conf < MIN_CONFIDENCE:
                    state["label"] = None; state["conf"] = conf
                else:
                    state["label"] = name; state["conf"] = conf
                    h = state["history"]
                    if not h or h[0]["label"] != name or time.time() - h[0]["t"] > 2:
                        h.insert(0, {"label": name, "conf": round(conf, 2), "db": round(db), "t": time.time()})
                        del h[HISTORY:]

# ---------------------------------------------------------------- web --
app = Flask(__name__)

@app.route("/state")
def get_state():
    with lock:
        return jsonify(state)

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
  <div id="top3"></div>
  <small style="margin-top:20px">front = up · laptop mic gives left/right only</small>
</div>
<div id="right"><h1>RECENT</h1><div id="hist"></div></div>
<script>
const C=%COLORS%;
const ticks=document.getElementById('ticks');
for(let i=0;i<12;i++){const a=i*30*Math.PI/180;const l=document.createElementNS('http://www.w3.org/2000/svg','line');
 l.setAttribute('x1',Math.sin(a)*84);l.setAttribute('y1',-Math.cos(a)*84);l.setAttribute('x2',Math.sin(a)*90);l.setAttribute('y2',-Math.cos(a)*90);ticks.appendChild(l);}
function wedge(angle,w){const a0=(angle-w)*Math.PI/180,a1=(angle+w)*Math.PI/180,R=90;
 return `M0 0 L${Math.sin(a0)*R} ${-Math.cos(a0)*R} A${R} ${R} 0 0 1 ${Math.sin(a1)*R} ${-Math.cos(a1)*R} Z`;}
let lastTs=0;
async function tick(){
 try{const s=await (await fetch('/state')).json();
  const col=C[s.label]||'#fff';
  document.getElementById('meterfill').style.width=Math.max(0,Math.min(100,(s.db+60)*100/60))+'%';
  const wd=document.getElementById('wedge'),pu=document.getElementById('pulse');
  if(s.label){
   document.getElementById('label').textContent=s.label.replace('_',' ');document.getElementById('label').style.color=col;
   document.getElementById('conf').textContent=Math.round(s.conf*100)+'% confident · '+Math.round(s.db)+' dB';
   if(s.angle!==null){wd.setAttribute('d',wedge(s.angle,25));wd.setAttribute('fill',col);wd.setAttribute('opacity',.8);pu.setAttribute('opacity',0);}
   else{wd.setAttribute('opacity',0);pu.setAttribute('stroke',col);pu.setAttribute('opacity',.9);}
  }else{document.getElementById('label').textContent=s.db<-50?'quiet':'…';document.getElementById('label').style.color='#556';
   document.getElementById('conf').textContent='';wd.setAttribute('opacity',0);pu.setAttribute('opacity',0);}
  document.getElementById('top3').textContent=(s.top3||[]).map(t=>t[0]+' '+Math.round(t[1]*100)+'%').join('   ');
  document.getElementById('hist').innerHTML=(s.history||[]).map(h=>`<div class="row"><span><span class="dot" style="background:${C[h.label]||'#fff'}"></span>${h.label.replace('_',' ')}</span><span>${Math.round(h.conf*100)}%</span></div>`).join('');
 }catch(e){}
 setTimeout(tick,150);}
tick();
</script></body></html>"""

@app.route("/")
def index():
    return Response(PAGE.replace("%COLORS%", json.dumps(COLORS)), mimetype="text/html")

if __name__ == "__main__":
    if "--list" in sys.argv:
        print(sd.query_devices()); sys.exit()
    dev = None
    if "--device" in sys.argv:
        dev = int(sys.argv[sys.argv.index("--device") + 1])
    threading.Thread(target=audio_loop, args=(dev,), daemon=True).start()
    print("open http://localhost:5050")
    app.run(host="127.0.0.1", port=5050, debug=False)
