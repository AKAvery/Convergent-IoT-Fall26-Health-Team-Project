#!/usr/bin/env python3
"""
Write reference outputs of the Python sound detector (demo/detector.py) for the Swift port
(week-1 tasks A4, checked by A5 and C4). Everything goes to fixtures/detector/ at the repo root;
the format is described in fixtures/detector/README.md.

30 clips, picked deterministically from the held-out test split (work/manifest.csv rows with
split == "test", via eval_pipeline.test_rows(): ESC-50 fold 5 + FSDD speaker "theo"):
  24  two clips per target class, peak -20 dBFS, 2 s of -70 dBFS white noise before and after
      (exactly eval_pipeline's `confusion` stream)
   2  ESC-50 "other" test clips, same stream
   1  white noise at -30 dBFS RMS (noise, nothing should fire)
   1  digital silence (gated every step)
   1  -80 dBFS white noise (below the -70 dBFS gate: gated every step)
   1  a target clip at -78 dBFS peak in -90 dBFS noise (a real sound that is too quiet: gated)

Each clip is streamed through a fresh Detector exactly the way the app runs it: 0.1 s blocks
into the 1 s ring buffer, YAMNet on the last 0.975 s. The detector code is imported, not copied.

    python3 export_detector_fixtures.py           # write fixtures/detector/
    python3 export_detector_fixtures.py --check   # re-run and confirm the files are reproduced exactly
"""
import sys, json, hashlib, argparse
from collections import defaultdict
from dataclasses import asdict
from pathlib import Path
import numpy as np

ML_DIR = Path(__file__).resolve().parent
REPO = ML_DIR.parent
sys.path.insert(0, str(ML_DIR)); sys.path.insert(0, str(REPO / "demo"))
from config import SAMPLE_RATE, MODELS_DIR, OTHER_LABEL, TEST_FOLD, TEST_SPEAKERS   # noqa: E402
from audio_utils import load_mono_16k                                             # noqa: E402
import eval_pipeline as ep                                                        # noqa: E402  (split + stream helpers)
from detector import Detector, DetectorParams, PRESETS, CLASS_PRIORITY, WINDOW    # noqa: E402

OUT_DIR = REPO / "fixtures" / "detector"
SEED = 2026
PER_CLASS = 2
N_OTHER = 2
PRESET = "all"
FORMAT_VERSION = 1
# A decision is "fragile" at a step when one of its comparisons is closer to its boundary than the
# Swift side can be expected to reproduce: probabilities are only checked to 1e-4 (C4), level_db is
# float32 arithmetic (a few 1e-5 dB). Fragile steps are flagged so a test can explain a mismatch.
PROB_EPS = 1e-4
DB_EPS = 0.01
SCORE_EPS = 1e-3


# ------------------------------------------------------------------ clips --
def white(rng, n, rms_db):
    return (rng.standard_normal(n) * 10 ** (rms_db / 20)).astype(np.float32)


def trim_to_hop(y, hop):
    return np.ascontiguousarray(y[: len(y) - len(y) % hop], dtype=np.float32)


def rel(p):
    try:
        return str(Path(p).resolve().relative_to(REPO))
    except ValueError:
        return str(p)


def choose_clips(names):
    """Deterministic pick from the test split. Returns a list of clip specs (audio built later)."""
    rows = ep.test_rows()
    by_label = defaultdict(list)
    for r in rows:
        by_label[r["label"]].append(r)
    rnd = np.random.default_rng(SEED)
    specs = []
    for lab in names:
        if lab == OTHER_LABEL:
            continue
        pool = sorted(by_label[lab], key=lambda r: (r["path"], r["offset"]))
        for k in sorted(rnd.choice(len(pool), size=PER_CLASS, replace=False)):
            specs.append({"kind": "target", "label": lab, "row": pool[k], "peak_db": ep.REF_LEVEL_DB})
    pool = sorted(by_label[OTHER_LABEL], key=lambda r: (r["path"], r["offset"]))
    for k in sorted(rnd.choice(len(pool), size=N_OTHER, replace=False)):
        specs.append({"kind": "other", "label": OTHER_LABEL, "row": pool[k], "peak_db": ep.REF_LEVEL_DB})
    specs.append({"kind": "noise", "label": OTHER_LABEL, "row": None, "rms_db": -30.0, "seconds": 4.0})
    specs.append({"kind": "silence", "label": None, "row": None, "seconds": 3.0})
    specs.append({"kind": "quiet_noise", "label": None, "row": None, "rms_db": -80.0, "seconds": 4.0})
    # a loud-in-real-life class at a level the gate must skip (siren's first pick, reused on purpose)
    siren = next(s for s in specs if s["label"] == "siren")
    specs.append({"kind": "quiet_target", "label": "siren", "row": siren["row"], "peak_db": -78.0, "bg_db": -90.0})
    return specs


def build_audio(spec, idx, hop):
    """The exact float32 stream fed to the detector. Per-clip RNG so one clip never shifts another."""
    rng = np.random.default_rng([SEED, idx])
    pad = int(ep.PAD_S * SAMPLE_RATE)
    kind = spec["kind"]
    if kind in ("target", "other"):
        r = spec["row"]
        clip = ep.set_peak(load_mono_16k(r["path"], r["offset"], r["duration"]), spec["peak_db"])
        bg = ep.Background(False, rng)                 # eval_pipeline's white noise at BG_NOISE_DB
        y = np.concatenate([bg.get(pad), clip, bg.get(pad)])
        desc = f"{ep.PAD_S:g} s white noise at {ep.BG_NOISE_DB} dBFS RMS, clip at {spec['peak_db']} dBFS peak, {ep.PAD_S:g} s noise"
    elif kind == "quiet_target":
        r = spec["row"]
        clip = ep.set_peak(load_mono_16k(r["path"], r["offset"], r["duration"]), spec["peak_db"])
        y = np.concatenate([white(rng, pad, spec["bg_db"]), clip + white(rng, len(clip), spec["bg_db"]),
                            white(rng, pad, spec["bg_db"])])
        desc = f"clip at {spec['peak_db']} dBFS peak over white noise at {spec['bg_db']} dBFS RMS, {ep.PAD_S:g} s noise each side"
    elif kind in ("noise", "quiet_noise"):
        y = white(rng, int(spec["seconds"] * SAMPLE_RATE), spec["rms_db"])
        desc = f"{spec['seconds']:g} s white noise at {spec['rms_db']} dBFS RMS"
    elif kind == "silence":
        y = np.zeros(int(spec["seconds"] * SAMPLE_RATE), dtype=np.float32)
        desc = f"{spec['seconds']:g} s of exact zeros"
    else:
        raise ValueError(kind)
    return trim_to_hop(y, hop), desc


# --------------------------------------------------------------- analysis --
def fragile_reasons(det, st):
    """Comparisons in this step that sit within the Swift tolerance of their boundary."""
    out = []
    if st["ready"] and abs(st["level_db"] - det.p.gate_db) < DB_EPS:
        out.append("gate")
    p = st["probs"]
    if p is None:
        return out
    names, thr, io = det.names, det.thr, det.i_other
    order = np.argsort(p)[::-1]
    if io is not None and (order[0] == io or order[1] == io) and p[order[0]] - p[order[1]] < PROB_EPS:
        out.append("other_top")
    other_top = io is not None and int(np.argmax(p)) == io
    for i, n in enumerate(names):
        if n == OTHER_LABEL:
            continue
        if abs(float(p[i]) - float(thr[i])) < PROB_EPS:
            out.append(f"threshold:{n}")
        if (det.p.other_veto and other_top and p[i] >= thr[i]
                and CLASS_PRIORITY.get(n, 1) < det.p.veto_exempt_priority
                and abs(float(p[i]) - float(p[io] + np.float32(det.p.other_veto_margin))) < PROB_EPS):
            out.append(f"veto:{n}")
    alerts = st["alerts"]
    if alerts and det.p.label_margin > 0 and CLASS_PRIORITY.get(alerts[0]["label"], 1) < det.p.veto_exempt_priority:
        i = names.index(alerts[0]["label"])
        rivals = [p[j] for j, n in enumerate(names) if n != OTHER_LABEL and j != i]
        if rivals and abs(float(p[i]) - float(max(rivals) + np.float32(det.p.label_margin))) < PROB_EPS:
            out.append("label_margin")
    if len(st["hits"]) >= 2 and abs(st["hits"][0]["score"] - st["hits"][1]["score"]) < SCORE_EPS:
        out.append("hit_order")
    return out


def coverage(det, st):
    """Which decision paths this step exercised (for the manifest summary only)."""
    c = set()
    if not st["ready"]:
        c.add("not_ready")
    elif st["gated"]:
        c.add("gated_by_level")
    if st["probs"] is None:
        return c
    p, io = st["probs"], det.i_other
    other_top = io is not None and int(np.argmax(p)) == io
    for i, n in enumerate(det.names):
        if n == OTHER_LABEL or p[i] < det.thr[i]:
            continue
        if (det.p.other_veto and other_top and CLASS_PRIORITY.get(n, 1) < det.p.veto_exempt_priority
                and p[i] < p[io] + det.p.other_veto_margin):
            c.add("other_veto")
        elif det.streak[n] < det.p.persist:
            c.add("waiting_for_persist")
    if st["hits"]:
        c.add("hit")
    if len(st["hits"]) >= 2:
        c.add("multiple_hits")
    if st["alerts"] and st["label"] is None:
        c.add("label_withheld_by_margin")
    if st["label"] is not None:
        c.add("label")
        if CLASS_PRIORITY.get(st["label"], 1) >= det.p.veto_exempt_priority:
            c.add("label_safety_exempt")
    return c


# ------------------------------------------------------------------- run --
def f32(x):
    """A float32 as the float64 with the same value (its repr round-trips to the same float32)."""
    return float(np.float32(x))


def run_clip(det, audio):
    det.reset()
    steps, cov, fragile = [], set(), []
    hop = det.hop
    for k in range(len(audio) // hop):
        st = det.process(audio[k * hop:(k + 1) * hop])
        reasons = fragile_reasons(det, st)
        cov |= coverage(det, st)
        if reasons:
            fragile.append(k)
        step = {
            "i": k,
            "t": round((k + 1) * hop / SAMPLE_RATE, 4),
            "ready": bool(st["ready"]),
            "level_db": float(st["level_db"]),
            "gated": bool(st["gated"]),
            "probs": None if st["probs"] is None else [f32(v) for v in st["probs"]],
            "hits": [{"label": h["label"], "conf": h["conf"], "score": h["score"]} for h in st["hits"]],
            "label": st["label"],
            "conf": float(st["conf"]),
            "streak": [int(det.streak[n]) for n in det.names],
        }
        if not st["gated"]:
            saved = det.preset
            other = {}
            for pr in PRESETS:
                if pr == PRESET:
                    continue
                det.preset = pr
                top, _ = det.pick_label(st["hits"], st["probs"])
                other[pr] = None if top is None else top["label"]
            det.preset = saved
            step["label_by_preset"] = other
        if reasons:
            step["fragile"] = reasons
        steps.append(step)
    return steps, cov, fragile


def sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def detector_block(det):
    return {
        "preset": PRESET,
        "sample_rate": SAMPLE_RATE,
        "hop_samples": det.hop,
        "buffer_samples": det.n_buf,
        "window_samples": WINDOW,
        "params": asdict(det.p),
        "labels": det.names,
        "thresholds": {n: f32(t) for n, t in zip(det.names, det.thr)},
        "class_priority": CLASS_PRIORITY,
        "presets": {k: (sorted(v) if v is not None else None) for k, v in PRESETS.items()},
    }


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="re-run and compare against the files in fixtures/detector/")
    args = ap.parse_args()

    det = Detector(DetectorParams.default(), preset=PRESET, model_dir=MODELS_DIR)
    specs = choose_clips(det.names)
    assert len(specs) == 30, len(specs)
    dblock = detector_block(det)
    models = {f: sha256(MODELS_DIR / f) for f in
              ("yamnet_embedding_metadata.tflite", "sound_head.tflite", "labels.json", "thresholds.json")}
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    entries, problems = [], []
    cov_total = defaultdict(int)
    for idx, spec in enumerate(specs):
        audio, desc = build_audio(spec, idx, det.hop)
        r = spec["row"]
        stem = Path(r["path"]).stem if r else spec["kind"]
        cid = f"{idx:02d}_{spec['kind'] if spec['kind'] != 'target' else spec['label']}_{stem}"
        if spec["kind"] == "quiet_target":
            cid = f"{idx:02d}_quiet_{spec['label']}_{stem}"
        steps, cov, fragile = run_clip(det, audio)
        for c in cov:
            cov_total[c] += 1
        doc = {
            "format_version": FORMAT_VERSION,
            "id": cid,
            "kind": spec["kind"],
            "true_label": spec["label"],
            "source": None if r is None else {
                "path": rel(r["path"]), "offset_s": r["offset"], "duration_s": r["duration"],
                "dataset": "esc50" if "ESC-50" in r["path"] else "fsdd",
            },
            "stream": desc,
            "audio": {"file": f"{cid}.bin", "dtype": "float32", "byte_order": "little", "channels": 1,
                      "sample_rate": SAMPLE_RATE, "num_samples": int(len(audio)),
                      "sha256": hashlib.sha256(audio.astype("<f4").tobytes()).hexdigest()},
            "detector": dblock,
            "num_steps": len(steps),
            "fragile_steps": fragile,
            "steps": steps,
        }
        bin_path, json_path = OUT_DIR / f"{cid}.bin", OUT_DIR / f"{cid}.json"
        if args.check:
            ok_audio = bin_path.exists() and bin_path.read_bytes() == audio.astype("<f4").tobytes()
            ok_json = json_path.exists() and json.loads(json_path.read_text()) == json.loads(json.dumps(doc))
            status = "ok" if ok_audio and ok_json else f"MISMATCH (audio {ok_audio}, json {ok_json})"
            if status != "ok":
                problems.append(cid)
        else:
            bin_path.write_bytes(audio.astype("<f4").tobytes())
            json_path.write_text(json.dumps(doc, separators=(",", ":")) + "\n")
            status = "written"
        fired = sorted({h["label"] for s in steps for h in s["hits"]})
        bigs = sorted({s["label"] for s in steps if s["label"]})
        n_gated = sum(s["gated"] for s in steps)
        print(f"{cid:44s} {len(audio) / SAMPLE_RATE:5.1f} s  gated {n_gated:3d}/{len(steps):3d}  "
              f"fired {fired or '-'}  big {bigs or '-'}  fragile {len(fragile)}  {status}", flush=True)
        entries.append({"id": cid, "kind": spec["kind"], "true_label": spec["label"],
                        "json": f"{cid}.json", "audio": f"{cid}.bin", "num_samples": int(len(audio)),
                        "num_steps": len(steps), "fired": fired, "big_labels": bigs,
                        "gated_steps": n_gated, "fragile_steps": fragile})

    manifest = {
        "format_version": FORMAT_VERSION,
        "generator": "ml/export_detector_fixtures.py",
        "seed": SEED,
        "split": f"test split of ml/work/manifest.csv (ESC-50 fold {TEST_FOLD}, FSDD speakers {sorted(TEST_SPEAKERS)})",
        "models": {"dir": rel(MODELS_DIR), "sha256": models},
        "detector": dblock,
        "tolerances": {"probs_abs": 1e-4, "decisions": "exact (gated, hits labels and order, label)"},
        "fragile_eps": {"prob": PROB_EPS, "level_db": DB_EPS, "score": SCORE_EPS},
        "coverage_clips": dict(sorted(cov_total.items())),
        "clips": entries,
    }
    man_path = OUT_DIR / "manifest.json"
    if args.check:
        old = json.loads(man_path.read_text()) if man_path.exists() else None
        if old != json.loads(json.dumps(manifest)):
            problems.append("manifest.json")
        print("CHECK FAILED: " + ", ".join(problems) if problems else "check passed: all fixtures reproduced exactly")
        sys.exit(1 if problems else 0)
    man_path.write_text(json.dumps(manifest, indent=1) + "\n")
    total = sum(p.stat().st_size for p in OUT_DIR.iterdir() if p.is_file())
    print(f"-> {rel(OUT_DIR)}  ({len(entries)} clips, {total / 1e6:.1f} MB)")
    print("coverage (clips exercising each path):", dict(sorted(cov_total.items())))


if __name__ == "__main__":
    main()
