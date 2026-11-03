#!/usr/bin/env python3
"""
Sound detector shared by the live demo (demo/live_demo.py) and the offline evaluation
harness (ml/eval_pipeline.py). Both must run byte-identical logic, so everything that turns
audio into labels lives here: YAMNet embedding + trained head, loudness gate, persistence,
"other" veto, priority scoring, presets.

Only numpy + TFLite are imported (no sounddevice, no flask) so the harness can import this
without audio hardware.

    det = Detector(DetectorParams.default(), preset="safety")
    for block in mono_16k_blocks_of(det.hop):      # det.hop samples per block
        s = det.process(block)                     # dict: label, conf, hits, alerts, gated, ...
"""
import json, math
from dataclasses import dataclass, asdict, field
from pathlib import Path
import numpy as np

try:
    import tflite_runtime.interpreter as tflite
except ImportError:
    import tensorflow.lite as tflite

PI_DIR = Path(__file__).resolve().parent.parent / "pi"
SAMPLE_RATE = 16000
WINDOW = 15600          # 0.975 s, what YAMNet expects

# How important each sound is when several are detected at once. Same table as
# ml/config.py (copied: the demo does not import ml/). score = priority * confidence * loudness.
CLASS_PRIORITY = {"siren": 10, "alarm": 10, "glass_break": 8, "car_horn": 9, "baby_cry": 7,
                  "knock": 5, "clap": 4, "dog": 3, "cat": 2, "appliance": 2, "speech": 2, "footsteps": 1}

# Which detected sounds count as alerts (shown big). "all" = no filter. Everything that
# fires is still reported in `hits` so the ambient feed keeps working.
PRESETS = {
    "all": None,
    "safety": {"siren", "alarm", "car_horn", "glass_break"},
    "babies": {"baby_cry"},
    "privacy": {"speech"},
    "household": {"knock", "dog", "cat", "appliance", "footsteps", "clap"},
}


@dataclass
class DetectorParams:
    """Every tunable in the pipeline. baseline() is the demo as it was before this module existed;
    default() is the current recommendation. The harness A/Bs the two."""
    # Measured with ml/eval_pipeline.py (2026-10-17): what matters for wrong labels is the time span
    # of evidence (hop * persist), not the count. 0.1 s hop with persist 2 doubled wrong labels and
    # false fires; persist 5 (0.5 s, same as the old 0.25 s hop x 2) brought both below the old demo
    # while the lower gate caught -40/-50 dBFS clips the old gate skipped entirely.
    hop_s: float = 0.10            # seconds of new audio per update (inference runs once per hop)
    buffer_s: float = 1.0          # ring buffer handed to the model (last WINDOW samples are used)
    gate_db: float = -70.0         # skip inference when level_db is below this
    gate_window_s: float = 0.10    # level_db = max RMS over sub-windows this long; 0 = RMS of whole buffer
    persist: int = 5               # consecutive updates over threshold before a class fires (0.5 s at hop 0.1)
    other_veto: bool = True        # if "other" is the top class, low-priority classes need a margin over it
    other_veto_margin: float = 0.15
    veto_exempt_priority: int = 8  # classes with priority >= this are never vetoed or margin-withheld
    label_margin: float = 0.10     # big label only if its prob beats the next non-other class by this
    loud_ref_db: float = -60.0     # loudness factor = clamp((level_db - ref) / 30, floor, 1)
    loud_floor: float = 0.2
    input_gain_db: float = 0.0     # digital gain applied before everything
    clip_level: float = 0.99       # |x| >= this counts as a clipped sample
    # Once a class has fired (streak >= persist) it stays on while its probability is >= this,
    # instead of its threshold. Conversation scores 0.4-0.95 from step to step, so with speech's
    # 0.8 threshold the label dropped out at every dip (box recording 2026-11-03, talkers a few
    # feet away: shown 26% of the time in 7 pieces; with 0.5, 44% in 3). Entry is unchanged, so it
    # starts no new fires: eval harness on the ADPCM chain identical in caught, wrong labels,
    # false fires, overlap and OOV; speech steps showing the label +4%, all correct.
    sustain: dict = field(default_factory=lambda: {"speech": 0.5})

    @classmethod
    def default(cls, **kw):
        return cls(**kw)

    @classmethod
    def baseline(cls, **kw):
        """demo/live_demo.py as of commit 5a426a8: 1 s RMS gate at -50 dB, 0.25 s hop, no veto."""
        base = dict(hop_s=0.25, gate_db=-50.0, gate_window_s=0.0, persist=2, other_veto=False,
                    label_margin=0.0, loud_ref_db=-50.0, sustain={})
        base.update(kw)
        return cls(**base)

    def describe(self):
        return ", ".join(f"{k}={v}" for k, v in asdict(self).items())


def dbfs(x):
    return 20 * math.log10(float(x) + 1e-9)


# ---------------------------------------------------------------- model --
class Classifier:
    """Frozen YAMNet embedding (TFLite) -> our trained multi-label head."""

    def __init__(self, model_dir=PI_DIR):
        model_dir = Path(model_dir)
        self.embed = tflite.Interpreter(model_path=str(model_dir / "yamnet_embedding_metadata.tflite"), num_threads=4)
        self.embed.allocate_tensors()
        self.e_in = self.embed.get_input_details()[0]["index"]
        self.e_out = self.embed.get_output_details()[0]["index"]
        self.head = tflite.Interpreter(model_path=str(model_dir / "sound_head.tflite"))
        self.head.allocate_tensors()
        self.h_in = self.head.get_input_details()[0]["index"]
        self.h_out = self.head.get_output_details()[0]["index"]
        self.names = json.loads((model_dir / "labels.json").read_text())
        try:
            t = json.loads((model_dir / "thresholds.json").read_text())
            self.thr = np.array([t.get(n, 0.5) for n in self.names])
        except FileNotFoundError:
            self.thr = np.full(len(self.names), 0.5)

    def probs(self, mono):
        """Sigmoid probability per class for the last WINDOW samples of `mono` (peak-normalised)."""
        mono = mono.astype(np.float32)
        peak = np.abs(mono).max()
        if peak > 0:
            mono = mono / peak * 0.5
        if len(mono) < WINDOW:
            mono = np.pad(mono, (0, WINDOW - len(mono)))
        w = mono[-WINDOW:]
        self.embed.set_tensor(self.e_in, w[np.newaxis, :]); self.embed.invoke()
        self.head.set_tensor(self.h_in, self.embed.get_tensor(self.e_out)); self.head.invoke()
        return self.head.get_tensor(self.h_out)[0]


# ------------------------------------------------------------- detector --
class Detector:
    def __init__(self, params=None, preset="all", classifier=None, model_dir=PI_DIR, thresholds=None):
        self.p = params or DetectorParams.default()
        self.net = classifier if classifier is not None else Classifier(model_dir)
        self.names = list(self.net.names)
        self.thr = np.array(thresholds if thresholds is not None else self.net.thr, dtype=np.float32)
        self.set_preset(preset)
        self.hop = int(round(self.p.hop_s * SAMPLE_RATE))
        self.n_buf = int(round(self.p.buffer_s * SAMPLE_RATE))
        self.gain = 10 ** (self.p.input_gain_db / 20)
        self.i_other = self.names.index("other") if "other" in self.names else None
        self.reset()

    def reset(self):
        self.buf = np.zeros(self.n_buf, dtype=np.float32)
        self.filled = 0
        self.streak = {n: 0 for n in self.names}

    def set_preset(self, preset):
        if preset not in PRESETS:
            raise ValueError(f"unknown preset {preset!r}; choose from {sorted(PRESETS)}")
        self.preset = preset

    # -- level measures ---------------------------------------------------
    def level_db(self):
        """What the gate and the loudness factor look at."""
        w = int(round(self.p.gate_window_s * SAMPLE_RATE))
        if w <= 0 or w >= len(self.buf):
            return dbfs(np.sqrt(np.mean(self.buf ** 2)))
        n = len(self.buf) // w
        chunks = self.buf[len(self.buf) - n * w:].reshape(n, w)
        return dbfs(np.sqrt(np.mean(chunks ** 2, axis=1)).max())

    # -- one update -------------------------------------------------------
    def process(self, block):
        """Feed `hop` new mono float32 samples at 16 kHz. Returns the detector state for this update.
        `probs` in the result is the raw numpy vector (None when gated); strip it before jsonify."""
        block = np.asarray(block, dtype=np.float32) * self.gain
        if len(block):
            self.buf = np.concatenate([self.buf, block])[-self.n_buf:]
            self.filled = min(self.filled + len(block), self.n_buf)
        rms_db = dbfs(np.sqrt(np.mean(self.buf ** 2)))
        level = self.level_db()
        st = {"ready": self.filled >= self.n_buf, "db": rms_db, "level_db": level,
              "peak_db": dbfs(np.abs(block).max()) if len(block) else -100.0,
              "clip_frac": float(np.mean(np.abs(block) >= self.p.clip_level)) if len(block) else 0.0,
              "gated": True, "label": None, "conf": 0.0, "top3": [], "hits": [], "alerts": [],
              "preset": self.preset, "gate_db": self.p.gate_db, "probs": None}
        if not st["ready"] or level < self.p.gate_db:
            return st
        st["gated"] = False
        p = self.net.probs(self.buf)
        st["probs"] = p
        hits, st["top3"] = self.decide(p, level)
        st["hits"] = hits
        top, st["alerts"] = self.pick_label(hits, p)
        if top is not None:
            st["label"], st["conf"] = top["label"], top["conf"]
        return st

    def decide(self, p, level_db):
        """Decision rule on one probability vector. Updates per-class streaks.
        Returns (hits sorted by score, top3 raw guesses). Used by process() and by the harness replay."""
        loud = min(1.0, max(self.p.loud_floor, (level_db - self.p.loud_ref_db) / 30))
        other_top = self.i_other is not None and int(np.argmax(p)) == self.i_other
        hits = []
        for i, name in enumerate(self.names):
            thr = self.thr[i]
            if self.streak[name] >= self.p.persist and name in self.p.sustain:
                thr = min(thr, np.float32(self.p.sustain[name]))     # already on: stay on (sustain)
            if name == "other" or p[i] < thr:
                self.streak[name] = 0; continue
            if (self.p.other_veto and other_top
                    and CLASS_PRIORITY.get(name, 1) < self.p.veto_exempt_priority
                    and p[i] < p[self.i_other] + self.p.other_veto_margin):
                self.streak[name] = 0; continue
            self.streak[name] += 1
            if self.streak[name] < self.p.persist:
                continue
            hits.append({"label": name, "conf": float(p[i]),
                         "score": CLASS_PRIORITY.get(name, 1) * float(p[i]) * loud})
        order = np.argsort(p)[::-1][:3]
        return sorted(hits, key=lambda h: -h["score"]), [(self.names[i], float(p[i])) for i in order]

    def pick_label(self, hits, p):
        """Big label = top alert for the active preset, withheld when a rival class is almost as
        likely (label_margin). Safety classes are never withheld."""
        allowed = PRESETS[self.preset]
        alerts = [h for h in hits if allowed is None or h["label"] in allowed]
        if not alerts:
            return None, alerts
        top = alerts[0]
        if self.p.label_margin > 0 and CLASS_PRIORITY.get(top["label"], 1) < self.p.veto_exempt_priority:
            i = self.names.index(top["label"])
            rivals = [p[j] for j, n in enumerate(self.names) if n != "other" and j != i]
            if rivals and p[i] < max(rivals) + self.p.label_margin:
                return None, alerts
        return top, alerts


def json_safe(state):
    """Copy of a process() result that jsonify can serialise (drops the numpy probs)."""
    out = {k: v for k, v in state.items() if k != "probs"}
    out["top3"] = [[n, round(c, 4)] for n, c in out["top3"]]
    return out
