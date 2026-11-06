#!/usr/bin/env python3
"""
Evaluate the LIVE detection pipeline (demo/detector.py: gate, hop, persistence, veto, scoring)
on the held-out test split, the way it actually runs: audio streamed in hop-sized blocks.

Two things are scored separately for every clip, because they are the two things we care about:
  caught      the true class fired at least once while the clip played
  wrong label another target class fired while the clip played (and whether it was shown big)

Scenarios
  confusion   every test clip at -20 dBFS peak           -> per-class caught / wrong / big-label accuracy
  levels      target clips at -10 .. -50 dBFS peak        -> caught + wrong per level, onset latency
  false       10 min of "other" clips + 5 min background  -> false fires per minute, per class + preset
  oov         ESC-50 categories we did NOT train on       -> which of our labels fire on them
  overlap     two target sounds mixed                      -> at-least-one / both / wrong
  thresholds  replay of `confusion` at thresholds 0.1..0.9 -> streaming precision/recall per class

    python3 eval_pipeline.py                      # default params, full report
    python3 eval_pipeline.py --params baseline    # the demo as it was before detector.py
    python3 eval_pipeline.py --compare            # baseline vs default + regression guard
    python3 eval_pipeline.py --quick              # 2 clips/class, 2 levels (smoke test)
    python3 eval_pipeline.py --playback           # through the real speakers + mic (be quiet!)

Reports go to work/eval_<tag>.md. Exit code 1 if --compare trips the regression guard.
"""
import sys, csv, json, math, random, time, argparse
from collections import Counter, defaultdict
from pathlib import Path
import numpy as np

ML_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ML_DIR)); sys.path.insert(0, str(ML_DIR.parent / "demo"))
from config import *                                   # noqa: E402
from audio_utils import load_mono_16k                  # noqa: E402
from detector import Detector, DetectorParams          # noqa: E402
from detector import PRESETS, CLASS_PRIORITY           # noqa: E402

LEVELS_DB = [-10, -20, -30, -40, -50]
REF_LEVEL_DB = -20
PAD_S = 2.0                      # background before and after each clip
BG_NOISE_DB = -70                # white-noise floor when DEMAND is not used
THR_GRID = [round(x, 2) for x in np.arange(0.10, 0.91, 0.05)]
GUARD_CAUGHT_DROP = 0.05         # regression guard: max allowed drop in caught rate at -20 dBFS
GUARD_FP_RISE = 0.2              # regression guard: max allowed rise in false fires / minute


# ------------------------------------------------------------------ data --
def test_rows():
    with open(WORK_DIR / "manifest.csv") as f:
        rows = [r for r in csv.DictReader(f) if r["split"] == "test"]
    for r in rows:
        r["offset"] = float(r.get("offset") or 0); r["duration"] = float(r.get("duration") or 0)
    return rows

def oov_rows():
    """ESC-50 test-fold clips whose category is not one of our targets (never seen as a *label*)."""
    with open(ESC50_DIR / "meta" / "esc50.csv") as f:
        esc = list(csv.DictReader(f))
    return [{"path": str(ESC50_DIR / "audio" / r["filename"]), "label": OTHER_LABEL, "category": r["category"],
             "offset": 0.0, "duration": 0.0}
            for r in esc if int(r["fold"]) == TEST_FOLD and r["category"] not in TARGETS]

def demand_chunks():
    if not DEMAND_DIR.exists():
        return []
    out = []
    for env in sorted(d for d in DEMAND_DIR.iterdir() if d.is_dir()):
        ch = env / "ch01.wav"
        if ch.exists():
            out.append(ch)
    return out

def set_peak(y, db):
    peak = np.abs(y).max()
    return y / peak * 10 ** (db / 20) if peak > 0 else y

def dbfs(x):
    return 20 * math.log10(float(x) + 1e-9)


class Background:
    """Background audio generator: white noise at BG_NOISE_DB, or random DEMAND chunks at -45 dBFS."""
    def __init__(self, use_demand, rng):
        self.rng = rng
        self.demand = demand_chunks() if use_demand else []
        self.cache = {}

    def get(self, n):
        if not self.demand:
            return (self.rng.standard_normal(n) * 10 ** (BG_NOISE_DB / 20)).astype(np.float32)
        p = self.demand[self.rng.integers(len(self.demand))]
        if p not in self.cache:
            self.cache[p] = load_mono_16k(p, 0.0, 60.0)
        y = self.cache[p]
        s = self.rng.integers(0, max(1, len(y) - n))
        chunk = np.resize(y[s:s + n], n)
        return set_peak(chunk, -45).astype(np.float32)


# --------------------------------------------------------------- stream --
def run_stream(det, audio, keep_probs=False):
    """Feed `audio` through a fresh detector state. Returns a list of per-hop frames:
    (t_seconds_at_block_end, hits_labels, big_label, gated, probs|None, level_db)."""
    det.reset()
    hop = det.hop
    frames = []
    for i in range(0, len(audio) - hop + 1, hop):
        s = det.process(audio[i:i + hop])
        frames.append(((i + hop) / SAMPLE_RATE, [h["label"] for h in s["hits"]], s["label"], s["gated"],
                       s["probs"] if keep_probs else None, s["level_db"]))
    return frames

def score_clip(frames, true_label, clip_start, names):
    """Attribute every fire from clip start onward to the clip."""
    targets = [n for n in names if n != OTHER_LABEL]
    fired, wrong_big, onset, big_n, big_ok = set(), Counter(), None, 0, 0
    for t, hits, big, gated, _, _ in frames:
        if t < clip_start:
            continue
        for h in hits:
            fired.add(h)
            if h == true_label and onset is None:
                onset = t - clip_start
        if big is not None:
            big_n += 1
            if big == true_label:
                big_ok += 1
            elif big in targets:
                wrong_big[big] += 1
    wrong = {h for h in fired if h != true_label and h in targets}
    return {"caught": true_label in fired, "wrong": wrong, "wrong_big": wrong_big,
            "onset": onset, "big_n": big_n, "big_ok": big_ok}

def episodes(frames):
    """Count fire episodes (class goes from off to on) per class."""
    on, eps = set(), Counter()
    for _, hits, *_ in frames:
        now = set(hits)
        for h in now - on:
            eps[h] += 1
        on = now
    return eps


# ------------------------------------------------------------- scenarios --
class Eval:
    def __init__(self, params, args, tag):
        self.args, self.tag = args, tag
        self.params = params
        thr = None
        if tag == "baseline" and (MODELS_DIR / "thresholds_cliplevel.json").exists() and not args.thresholds:
            # the thresholds the old demo shipped with (train_head.py's clip-level calibration)
            args = argparse.Namespace(**{**vars(args), "thresholds": str(MODELS_DIR / "thresholds_cliplevel.json")})
        if args.thresholds:
            t = json.loads(Path(args.thresholds).read_text())
            names = json.loads((Path(args.model_dir) / "labels.json").read_text())
            thr = [t.get(n, 0.5) for n in names]
        self.det = Detector(params, preset="all", model_dir=Path(args.model_dir), thresholds=thr)
        self.names = self.det.names
        self.targets = [n for n in self.names if n != OTHER_LABEL]
        self.rng = np.random.default_rng(0); random.seed(0)
        self.bg = Background(args.demand, self.rng)
        rows = test_rows()
        self.by_label = defaultdict(list)
        for r in rows:
            self.by_label[r["label"]].append(r)
        if args.quick:
            for k in self.by_label:
                self.by_label[k] = self.by_label[k][:2]
        self.audio_cache = {}
        self.R = {}          # results
        self.lines = []      # report

    def load(self, r):
        key = (r["path"], r["offset"])
        if key not in self.audio_cache:
            self.audio_cache[key] = load_mono_16k(r["path"], r["offset"], r["duration"])
        return self.audio_cache[key]

    def stream_for(self, clip, level_db):
        pad = int(PAD_S * SAMPLE_RATE)
        y = set_peak(clip, level_db)
        return np.concatenate([self.bg.get(pad), y, self.bg.get(pad)]).astype(np.float32)

    def say(self, s=""):
        self.lines.append(s)

    # -- confusion (+ probs kept for the threshold replay) ------------------
    def confusion(self):
        per = {n: [] for n in self.names}
        self.replay = []     # (true_label, frames with probs) for threshold sweep
        fired_matrix = Counter()
        for lab, rows in self.by_label.items():
            for r in rows:
                frames = run_stream(self.det, self.stream_for(self.load(r), REF_LEVEL_DB), keep_probs=True)
                sc = score_clip(frames, lab, PAD_S, self.names)
                per[lab].append(sc)
                self.replay.append((lab, frames))
                for f in {h for _, hits, *_ in frames for h in hits}:
                    fired_matrix[(lab, f)] += 1
        self.R["confusion"] = per
        self.say("## Streamed confusion (every test clip at -20 dBFS peak)\n")
        self.say("| class | n | caught | wrong label | wrong shown big | big-label acc | onset med / p90 s |")
        self.say("|---|---|---|---|---|---|---|")
        agg = {"caught": [], "wrong": []}
        for lab in self.targets:
            scs = per[lab]
            if not scs: continue
            caught = np.mean([s["caught"] for s in scs]); wrong = np.mean([bool(s["wrong"]) for s in scs])
            wbig = np.mean([bool(s["wrong_big"]) for s in scs])
            bn = sum(s["big_n"] for s in scs); bo = sum(s["big_ok"] for s in scs)
            ons = [s["onset"] for s in scs if s["onset"] is not None]
            agg["caught"].append(caught); agg["wrong"].append(wrong)
            self.say(f"| {lab} | {len(scs)} | {caught:.2f} | {wrong:.2f} | {wbig:.2f} | "
                     f"{(bo / bn if bn else float('nan')):.2f} | "
                     f"{(np.median(ons) if ons else float('nan')):.2f} / {(np.percentile(ons, 90) if ons else float('nan')):.2f} |")
        self.say(f"| **mean** | | **{np.mean(agg['caught']):.2f}** | **{np.mean(agg['wrong']):.2f}** | | | |")
        oth = per[OTHER_LABEL]
        if oth:
            self.say(f"\n'other' test clips with any target fired: {np.mean([bool(s['wrong']) for s in oth]):.2f} (n={len(oth)})")
        self.R["confusion_summary"] = {lab: {"caught": float(np.mean([s["caught"] for s in per[lab]])),
                                             "wrong": float(np.mean([bool(s["wrong"]) for s in per[lab]]))}
                                       for lab in self.targets if per[lab]}
        # fired matrix
        self.say("\nFired-class matrix (rows = true, cols = fired at least once; clips):\n")
        cols = self.targets
        self.say("| true \\ fired | " + " | ".join(c[:5] for c in cols) + " |")
        self.say("|---|" + "---|" * len(cols))
        for lab in self.targets + [OTHER_LABEL]:
            if not per[lab]: continue
            self.say(f"| {lab} | " + " | ".join(str(fired_matrix[(lab, c)]) if fired_matrix[(lab, c)] else "·" for c in cols) + " |")
        self.say()

    # -- level sweep ----------------------------------------------------------
    def levels(self):
        levels = [-20, -40] if self.args.quick else LEVELS_DB
        res = {lv: {n: [] for n in self.targets} for lv in levels}
        for lab in self.targets:
            for r in self.by_label[lab]:
                clip = self.load(r)
                for lv in levels:
                    frames = run_stream(self.det, self.stream_for(clip, lv))
                    res[lv][lab].append(score_clip(frames, lab, PAD_S, self.names))
        self.R["levels"] = res
        self.say("## Level sweep (clip peak dBFS; digital attenuation, no room)\n")
        self.say("Caught rate:\n")
        self.say("| class | " + " | ".join(f"{lv} dB" for lv in levels) + " |")
        self.say("|---|" + "---|" * len(levels))
        for lab in self.targets:
            self.say(f"| {lab} | " + " | ".join(f"{np.mean([s['caught'] for s in res[lv][lab]]):.2f}" for lv in levels) + " |")
        self.say("| **mean** | " + " | ".join(f"**{np.mean([s['caught'] for l in self.targets for s in res[lv][l]]):.2f}**" for lv in levels) + " |")
        self.say("\nWrong-label rate:\n")
        self.say("| class | " + " | ".join(f"{lv} dB" for lv in levels) + " |")
        self.say("|---|" + "---|" * len(levels))
        for lab in self.targets:
            self.say(f"| {lab} | " + " | ".join(f"{np.mean([bool(s['wrong']) for s in res[lv][lab]]):.2f}" for lv in levels) + " |")
        self.say("| **mean** | " + " | ".join(f"**{np.mean([bool(s['wrong']) for l in self.targets for s in res[lv][l]]):.2f}**" for lv in levels) + " |")
        self.say("\nOnset latency (s after clip start, caught clips only):\n")
        self.say("| level | median | p90 | n |")
        self.say("|---|---|---|---|")
        for lv in levels:
            ons = [s["onset"] for l in self.targets for s in res[lv][l] if s["onset"] is not None]
            if ons:
                self.say(f"| {lv} dB | {np.median(ons):.2f} | {np.percentile(ons, 90):.2f} | {len(ons)} |")
        self.say()

    # -- false fires ----------------------------------------------------------
    def false_fires(self):
        others = self.by_label[OTHER_LABEL]
        if self.args.quick:
            others = others[:12]
        parts = [set_peak(self.load(r), REF_LEVEL_DB) for r in others]
        clips = np.concatenate(parts).astype(np.float32) if parts else np.zeros(0, np.float32)
        bg_minutes = 1 if self.args.quick else 5
        bg = self.bg.get(int(bg_minutes * 60 * SAMPLE_RATE))
        out = {}
        for name, audio in (("other clips", clips), ("background only", bg)):
            if len(audio) == 0: continue
            eps = episodes(run_stream(self.det, audio))
            minutes = len(audio) / SAMPLE_RATE / 60
            out[name] = {"minutes": minutes, "episodes": eps}
        self.R["false"] = out
        self.say("## False fires (fire episodes per minute)\n")
        self.say("| source | minutes | total/min | " + " | ".join(p for p in PRESETS if p != "all") + " | worst classes |")
        self.say("|---|---|---|" + "---|" * (len(PRESETS) - 1) + "---|")
        for name, o in out.items():
            eps, m = o["episodes"], o["minutes"]
            presets = " | ".join(f"{sum(c for k, c in eps.items() if k in PRESETS[p]) / m:.2f}" for p in PRESETS if p != "all")
            worst = ", ".join(f"{k} {c / m:.2f}" for k, c in eps.most_common(3))
            self.say(f"| {name} | {m:.1f} | {sum(eps.values()) / m:.2f} | {presets} | {worst or '—'} |")
        self.say()

    # -- out of vocabulary -------------------------------------------------------
    def oov(self):
        rows = oov_rows()
        if self.args.quick:
            rows = rows[::8]
        by_cat = defaultdict(Counter); n_by_cat = Counter(); any_fire = 0
        for r in rows:
            frames = run_stream(self.det, self.stream_for(load_mono_16k(r["path"]), REF_LEVEL_DB))
            eps = episodes(frames)
            n_by_cat[r["category"]] += 1
            if eps: any_fire += 1
            by_cat[r["category"]].update({k: 1 for k in eps})     # clips in which k fired
        self.R["oov"] = {"n": len(rows), "any_fire": any_fire}
        self.say("## Out-of-vocabulary sounds (ESC-50 test-fold categories we never trained as labels)\n")
        self.say(f"{any_fire}/{len(rows)} clips made some target class fire. Categories with fires, most first "
                 f"(fraction of that category's clips in which each label fired):\n")
        self.say("| ESC-50 category | n | fired as |")
        self.say("|---|---|---|")
        ranked = sorted(by_cat.items(), key=lambda kv: -sum(kv[1].values()))
        for cat, c in ranked:
            if not c: continue
            self.say(f"| {cat} | {n_by_cat[cat]} | " + ", ".join(f"{k} {v / n_by_cat[cat]:.2f}" for k, v in c.most_common()) + " |")
        self.say()

    # -- overlap -----------------------------------------------------------------
    def overlap(self):
        pairs = []
        rows = [(lab, r) for lab in self.targets if lab != SPEECH_LABEL or True for r in self.by_label[lab]]
        n_pairs = 24 if self.args.quick else 117
        rnd = random.Random(0)
        while len(pairs) < n_pairs:
            (la, ra), (lb, rb) = rnd.sample(rows, 2)
            if la != lb:
                pairs.append((la, ra, lb, rb))
        one = both = wrong = 0
        for la, ra, lb, rb in pairs:
            a = set_peak(self.load(ra), 0); b = set_peak(self.load(rb), 0)
            n = max(len(a), len(b)); a = np.resize(a, n); b = np.resize(b, n)
            ratio = rnd.uniform(*OVERLAP_RATIO_DB)
            mixed = a + b * 10 ** (ratio / 20)
            frames = run_stream(self.det, self.stream_for(mixed, REF_LEVEL_DB))
            fired = {h for t, hits, *_ in frames if t >= PAD_S for h in hits}
            one += bool(fired & {la, lb}); both += ({la, lb} <= fired)
            wrong += bool(fired - {la, lb})
        n = len(pairs)
        self.R["overlap"] = {"one": one / n, "both": both / n, "wrong": wrong / n}
        self.say("## Overlap (two target sounds mixed, second at -12..+6 dB; reported only)\n")
        self.say(f"| pairs | at least one | both | a third class fired |\n|---|---|---|---|\n"
                 f"| {n} | {one / n:.2f} | {both / n:.2f} | {wrong / n:.2f} |\n")

    # -- threshold replay ---------------------------------------------------------
    def thresholds(self):
        """Replay the confusion streams through Detector.decide at a grid of thresholds (all classes
        set to the same value: a class's firing depends only on its own threshold). Also a 2-fold
        cross-check: thresholds picked on half of the clips, scored on the other half."""
        det = self.det
        saved = det.thr.copy()
        labs = [lab for lab, _ in self.replay]
        n_clips = Counter(labs)
        fired_at = {}                      # t -> list (aligned with self.replay) of fired label sets
        for t in THR_GRID:
            det.thr = np.full(len(self.names), t, dtype=np.float32)
            out = []
            for lab, frames in self.replay:
                det.reset()
                fired = set()
                for ft, _, _, gated, p, level in frames:
                    if gated or p is None: continue
                    hits, _ = det.decide(p, level)
                    if ft >= PAD_S:
                        fired.update(h["label"] for h in hits)
                out.append(fired)
            fired_at[t] = out
        det.thr = saved; det.reset()

        def beta_for(c):
            pri = CLASS_PRIORITY.get(c, 1)
            return 2.0 if pri >= 7 else (1.0 if pri >= 4 else 0.7)

        def counts(c, t, idx):
            tp = sum(1 for i in idx if labs[i] == c and c in fired_at[t][i])
            fp = sum(1 for i in idx if labs[i] != c and c in fired_at[t][i])
            n = sum(1 for i in idx if labs[i] == c)
            return tp, fp, n

        def fbeta(c, t, idx):
            tp, fp, n = counts(c, t, idx); fn = n - tp; b = beta_for(c)
            return (1 + b ** 2) * tp / max(1e-9, (1 + b ** 2) * tp + b ** 2 * fn + fp)

        def nearest(x):
            return min(THR_GRID, key=lambda t: abs(t - float(x)))

        all_idx = list(range(len(labs)))
        self.say("## Threshold sweep under the streaming rule (confusion streams replayed)\n")
        self.say("beta as in train_head.py: 2.0 for priority>=7, 1.0 for >=4, else 0.7. "
                 "'suggested' is the F-beta argmax on these same clips (optimistic); nothing is written.\n")
        self.say("| class | current thr | recall @cur | FP clips @cur | suggested thr | recall @sug | FP clips @sug | F-beta cur -> sug |")
        self.say("|---|---|---|---|---|---|---|---|")
        sugg = {}
        total = len(labs)
        for i, c in enumerate(self.names):
            if c == OTHER_LABEL or n_clips[c] == 0: continue
            cur = nearest(saved[i]); best = max(THR_GRID, key=lambda t: fbeta(c, t, all_idx))
            sugg[c] = best
            tpc, fpc, n = counts(c, cur, all_idx); tpb, fpb, _ = counts(c, best, all_idx)
            self.say(f"| {c} | {saved[i]:.2f} | {tpc / n:.2f} | {fpc} / {total - n} | "
                     f"{best:.2f} | {tpb / n:.2f} | {fpb} / {total - n} | {fbeta(c, cur, all_idx):.2f} -> {fbeta(c, best, all_idx):.2f} |")
        self.R["thr_suggest"] = sugg
        # "safe" variant: take the suggestion only where it costs no recall on these clips
        self.R["thr_safe"] = {c: (sugg[c] if counts(c, sugg[c], all_idx)[0] >= counts(c, nearest(saved[i]), all_idx)[0]
                                  else float(saved[i]))
                              for i, c in enumerate(self.names) if c in sugg}

        # -- 2-fold cross-check -------------------------------------------------
        def clip_metrics(thr_by_class, idx):
            caught, wrong, other_fire, n_t, n_o = 0, 0, 0, 0, 0
            for i in idx:
                fired = {c for c, t in thr_by_class.items() if c in fired_at[t][i]}
                if labs[i] == OTHER_LABEL:
                    n_o += 1; other_fire += bool(fired)
                else:
                    n_t += 1; caught += labs[i] in fired; wrong += bool(fired - {labs[i]})
            return caught / max(1, n_t), wrong / max(1, n_t), other_fire / max(1, n_o)
        cur_thr = {c: nearest(saved[i]) for i, c in enumerate(self.names) if c != OTHER_LABEL}
        halves = [all_idx[0::2], all_idx[1::2]]
        cv_rows, cur_rows = [], []
        for k in (0, 1):
            pick, score = halves[1 - k], halves[k]
            thr_cv = {}
            for c in cur_thr:
                n_pick = sum(1 for i in pick if labs[i] == c)
                thr_cv[c] = max(THR_GRID, key=lambda t: fbeta(c, t, pick)) if n_pick else cur_thr[c]
            cv_rows.append(clip_metrics(thr_cv, score)); cur_rows.append(clip_metrics(cur_thr, score))
        cv = np.mean(cv_rows, axis=0); cu = np.mean(cur_rows, axis=0)
        self.R["thr_cv"] = {"cur": cu.tolist(), "cv": cv.tolist()}
        self.say("\nHonest estimate (2-fold: thresholds picked on one half of the clips, scored on the other half):\n")
        self.say("| thresholds | caught | wrong label | other clips with a fire |")
        self.say("|---|---|---|---|")
        self.say(f"| current (thresholds.json) | {cu[0]:.2f} | {cu[1]:.2f} | {cu[2]:.2f} |")
        self.say(f"| picked on the other half | {cv[0]:.2f} | {cv[1]:.2f} | {cv[2]:.2f} |")
        self.say()

    # -- all ------------------------------------------------------------------------
    def run(self):
        t0 = time.time()
        self.say(f"# Live-pipeline evaluation: {self.tag}\n")
        self.say(f"params: `{self.params.describe()}`  ")
        self.say(f"model: `{Path(self.args.model_dir).resolve()}`"
                 + (f" thresholds: `{self.args.thresholds}`" if self.args.thresholds else "") + "  ")
        self.say(f"background: {'DEMAND chunks at -45 dBFS' if self.bg.demand else f'white noise at {BG_NOISE_DB} dBFS'}  ")
        self.say(f"test split: {sum(len(v) for v in self.by_label.values())} clips from work/manifest.csv"
                 f"{' (quick subset)' if self.args.quick else ''}\n")
        self.say("> Digital attenuation has no room acoustics or mic self-noise, so the -40/-50 dB rows measure the gate "
                 "and ranking, not the microphone. `--playback` is the honest test of the laptop setup.\n")
        for step in (self.confusion, self.levels, self.false_fires, self.oov, self.overlap, self.thresholds):
            print(f"  [{self.tag}] {step.__name__} ...", flush=True)
            step()
        self.say(f"_{time.time() - t0:.0f} s_\n")
        import pickle
        (WORK_DIR / f"eval_{self.tag}.pkl").write_bytes(pickle.dumps(
            {"R": self.R, "targets": self.targets, "tag": self.tag, "params": self.params}))
        return self

    def report(self):
        return "\n".join(self.lines)


class Loaded:
    """A finished run restored from work/eval_<tag>.pkl (enough for compare())."""
    def __init__(self, path):
        import pickle
        d = pickle.loads(Path(path).read_bytes())
        self.R, self.targets, self.tag, self.params = d["R"], d["targets"], d["tag"], d["params"]


def write_thresholds(path, R):
    """Write the F-beta suggestions to `path` and the no-recall-loss variant to <stem>_safe.json.
    Both include "other" (unused at runtime) so the file is a drop-in for pi/thresholds.json."""
    for name, key in ((path, "thr_suggest"), (path.with_name(path.stem + "_safe" + path.suffix), "thr_safe")):
        d = dict(sorted({**R[key], OTHER_LABEL: 0.3}.items()))
        name.write_text(json.dumps(d, indent=1) + "\n"); print(f"{key} -> {name}")


# ---------------------------------------------------------------- compare --
def compare(base, new):
    lines = [f"# Compare: {base.tag} -> {new.tag}\n",
             f"base: `{base.params.describe()}`  \nnew:  `{new.params.describe()}`\n",
             "## Per class at -20 dBFS\n",
             "| class | caught base -> new | wrong base -> new |", "|---|---|---|"]
    fails = []
    for c in new.targets:
        b, n = base.R["confusion_summary"].get(c), new.R["confusion_summary"].get(c)
        if not b or not n: continue
        flag = ""
        if n["caught"] < b["caught"] - GUARD_CAUGHT_DROP:
            flag = " **REGRESSION**"; fails.append(f"{c}: caught {b['caught']:.2f} -> {n['caught']:.2f}")
        lines.append(f"| {c} | {b['caught']:.2f} -> {n['caught']:.2f}{flag} | {b['wrong']:.2f} -> {n['wrong']:.2f} |")
    lines.append("\n## Mean caught / wrong per level\n")
    levels = sorted(set(base.R["levels"]) & set(new.R["levels"]))
    lines += ["| level | caught base -> new | wrong base -> new |", "|---|---|---|"]
    for lv in levels:
        cb = np.mean([s["caught"] for l in base.targets for s in base.R["levels"][lv][l]])
        cn = np.mean([s["caught"] for l in new.targets for s in new.R["levels"][lv][l]])
        wb = np.mean([bool(s["wrong"]) for l in base.targets for s in base.R["levels"][lv][l]])
        wn = np.mean([bool(s["wrong"]) for l in new.targets for s in new.R["levels"][lv][l]])
        lines.append(f"| {lv} dB | {cb:.2f} -> {cn:.2f} | {wb:.2f} -> {wn:.2f} |")
    lines.append("\n## False fires per minute\n")
    lines += ["| source | total base -> new | " + " | ".join(p for p in PRESETS if p != "all") + " |",
              "|---|---|" + "---|" * (len(PRESETS) - 1)]
    for src in new.R["false"]:
        if src not in base.R["false"]: continue
        b, n = base.R["false"][src], new.R["false"][src]
        tb, tn = sum(b["episodes"].values()) / b["minutes"], sum(n["episodes"].values()) / n["minutes"]
        flag = ""
        if tn > tb + GUARD_FP_RISE:
            flag = " **REGRESSION**"; fails.append(f"{src}: false fires/min {tb:.2f} -> {tn:.2f}")
        cells = []
        for p in PRESETS:
            if p == "all": continue
            pb = sum(c for k, c in b["episodes"].items() if k in PRESETS[p]) / b["minutes"]
            pn = sum(c for k, c in n["episodes"].items() if k in PRESETS[p]) / n["minutes"]
            cells.append(f"{pb:.2f} -> {pn:.2f}")
        lines.append(f"| {src} | {tb:.2f} -> {tn:.2f}{flag} | " + " | ".join(cells) + " |")
    ob, on = base.R["overlap"], new.R["overlap"]
    lines.append(f"\n## Overlap\n\nat least one {ob['one']:.2f} -> {on['one']:.2f}, both {ob['both']:.2f} -> {on['both']:.2f}, "
                 f"third class {ob['wrong']:.2f} -> {on['wrong']:.2f}\n")
    lines.append(f"\n## OOV\n\nclips with any fire: {base.R['oov']['any_fire']}/{base.R['oov']['n']} -> "
                 f"{new.R['oov']['any_fire']}/{new.R['oov']['n']}\n")
    lines.append("\n## Regression guard\n")
    if fails:
        lines.append("**FAILED**: " + "; ".join(fails))
    else:
        lines.append(f"passed (no class lost more than {GUARD_CAUGHT_DROP:.2f} caught rate at -20 dBFS, "
                     f"no source gained more than {GUARD_FP_RISE} false fires/min)")
    return "\n".join(lines) + "\n", not fails


# --------------------------------------------------------------- playback --
class _Duplex:
    """One full-duplex stream kept open for the whole session.

    sd.playrec / sd.rec open and stop a CoreAudio stream per call, and on macOS the stop
    occasionally deadlocks inside PortAudio (AudioOutputUnitStop waiting on a CoreAudio mutex),
    which froze whole --playback runs after the first clip. Opening the stream once and feeding
    clips through its callback avoids the stop until the end.
    """

    def __init__(self, sd, sr):
        import threading
        self.sd, self.sr, self.job = sd, sr, None
        self._lock = threading.Lock()
        self.stream = sd.Stream(samplerate=sr, channels=1, dtype="float32", callback=self._cb)
        self.stream.start()
        self.run(np.zeros(sr // 2, dtype=np.float32))  # warm-up: the first blocks after start are junk

    def _cb(self, indata, outdata, frames, time_info, status):
        job = self.job
        if job is None:
            outdata.fill(0); return
        out, rec, done = job["out"], job["rec"], job["done"]
        pos = job["pos"]; k = min(frames, len(out) - pos)
        rec[pos:pos + k] = indata[:k, 0]
        outdata[:k, 0] = out[pos:pos + k]
        if k < frames:
            outdata[k:, 0] = 0
        job["pos"] = pos + k
        if job["pos"] >= len(out):
            self.job = None
            done.set()

    def run(self, out):
        """Play `out` (float32 mono at self.sr) and return what the mic recorded meanwhile."""
        import threading
        out = np.ascontiguousarray(out, dtype=np.float32)
        job = {"out": out, "rec": np.zeros(len(out), dtype=np.float32), "pos": 0, "done": threading.Event()}
        self.job = job
        if not job["done"].wait(timeout=len(out) / self.sr + 5.0):
            self.job = None
            print(f"  playback stalled after {job['pos']}/{len(out)} samples; scoring the partial recording")
        return job["rec"]

    def close(self):
        try:
            self.stream.stop(); self.stream.close()
        except Exception:
            pass


def playback(params, args):
    """Play test clips through the speakers at several volumes while recording the mic; score the recording."""
    try:
        import sounddevice as sd
    except ImportError:
        sys.exit("pip install sounddevice (in this venv) for --playback")
    import resampy
    det = Detector(params, preset="all", model_dir=Path(args.model_dir))
    names = det.names
    rows = test_rows()
    by_label = defaultdict(list)
    for r in rows:
        by_label[r["label"]].append(r)
    picks = [(lab, r) for lab in names if lab != OTHER_LABEL for r in by_label[lab][:args.per_class]]
    picks += [(OTHER_LABEL, r) for r in by_label[OTHER_LABEL][:10]]
    volumes = [float(v) for v in args.volumes.split(",")]
    sd.default.samplerate = SAMPLE_RATE; sd.default.channels = 1
    play_sr = SAMPLE_RATE
    try:
        sd.check_output_settings(samplerate=SAMPLE_RATE); sd.check_input_settings(samplerate=SAMPLE_RATE)
    except Exception:
        play_sr = 48000
    total_s = sum(len(load_mono_16k(r["path"], r["offset"], r["duration"])) / SAMPLE_RATE + 2.0 for _, r in picks) * len(volumes)
    print(f"output: {sd.query_devices(kind='output')['name']}   input: {sd.query_devices(kind='input')['name']}   rate {play_sr}")
    print(f"{len(picks)} clips x {len(volumes)} volumes ~ {total_s / 60:.1f} min. Set the Mac volume where you normally test, "
          f"then stay quiet.")
    input("Enter to measure the room noise floor (2 s) and start... ")
    dup = _Duplex(sd, play_sr)
    noise = dup.run(np.zeros(int(2 * play_sr), dtype=np.float32))
    print(f"room floor: {dbfs(np.sqrt(np.mean(noise ** 2))):.0f} dBFS RMS, peak {dbfs(np.abs(noise).max()):.0f} dBFS")
    res = {v: {"scores": defaultdict(list), "peak": [], "clip": []} for v in volumes}
    lines = [f"# Playback evaluation ({params.describe()})\n",
             f"room floor {dbfs(np.sqrt(np.mean(noise ** 2))):.0f} dBFS RMS; rate {play_sr}; "
             f"{len(picks)} clips x volumes {volumes}\n"]
    for k, (lab, r) in enumerate(picks):
        clip = set_peak(load_mono_16k(r["path"], r["offset"], r["duration"]), -3)
        for v in volumes:
            sig = np.concatenate([np.zeros(SAMPLE_RATE), clip * v, np.zeros(SAMPLE_RATE)]).astype(np.float32)
            out = sig if play_sr == SAMPLE_RATE else resampy.resample(sig, SAMPLE_RATE, play_sr).astype(np.float32)
            rec = dup.run(out)
            if play_sr != SAMPLE_RATE:
                rec = resampy.resample(rec, play_sr, SAMPLE_RATE)
            rec = np.nan_to_num(rec).astype(np.float32)
            frames = run_stream(det, rec)
            sc = score_clip(frames, lab, 1.0, names)
            res[v]["scores"][lab].append(sc)
            res[v]["peak"].append(dbfs(np.abs(rec).max()))
            res[v]["clip"].append(float(np.mean(np.abs(rec) >= params.clip_level)))
            fired = sorted({h for t, hits, *_ in frames if t >= 1.0 for h in hits})
            print(f"  {k + 1}/{len(picks)} {lab:12s} vol {v:<4} rec peak {res[v]['peak'][-1]:5.0f} dBFS  fired {fired or '—'}")
    lines += ["| volume | rec peak dBFS (median) | clipped frac (max) | caught (targets) | wrong label | other clips w/ fire |",
              "|---|---|---|---|---|---|"]
    for v in volumes:
        S = res[v]["scores"]
        tg = [s for lab, L in S.items() if lab != OTHER_LABEL for s in L]
        ot = S.get(OTHER_LABEL, [])
        lines.append(f"| {v} | {np.median(res[v]['peak']):.0f} | {max(res[v]['clip']):.3f} | "
                     f"{np.mean([s['caught'] for s in tg]):.2f} | {np.mean([bool(s['wrong']) for s in tg]):.2f} | "
                     f"{(np.mean([bool(s['wrong']) for s in ot]) if ot else float('nan')):.2f} |")
    lines.append("\nPer class caught / wrong at each volume:\n")
    lines.append("| class | " + " | ".join(str(v) for v in volumes) + " |")
    lines.append("|---|" + "---|" * len(volumes))
    for lab in names:
        if lab == OTHER_LABEL or not res[volumes[0]]["scores"].get(lab): continue
        lines.append(f"| {lab} | " + " | ".join(
            f"{np.mean([s['caught'] for s in res[v]['scores'][lab]]):.2f} / {np.mean([bool(s['wrong']) for s in res[v]['scores'][lab]]):.2f}"
            for v in volumes) + " |")
    dup.close()
    text = "\n".join(lines) + "\n"
    out = WORK_DIR / f"eval_playback_{args.params}.md"
    out.write_text(text); print(text); print(f"-> {out}")


# ------------------------------------------------------------------- main --
def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--params", default="default", choices=["baseline", "default"])
    ap.add_argument("--compare", action="store_true", help="run baseline and default, print deltas + regression guard")
    ap.add_argument("--quick", action="store_true", help="2 clips per class, 2 levels")
    ap.add_argument("--demand", action="store_true", help="use DEMAND room recordings as background if present")
    ap.add_argument("--model-dir", default=str(ML_DIR.parent / "pi"), help="folder with the .tflite + labels + thresholds")
    ap.add_argument("--set", action="append", default=[], metavar="KEY=VALUE",
                    help="override a DetectorParams field for the non-baseline run, e.g. --set gate_db=-65 --set persist=3")
    ap.add_argument("--tag", default=None, help="name for the report file")
    ap.add_argument("--thresholds", default=None, metavar="JSON",
                    help="per-class thresholds to use for the non-baseline run instead of <model-dir>/thresholds.json")
    ap.add_argument("--write-suggested", default=None, metavar="JSON",
                    help="write the threshold sweep's F-beta suggestions for the non-baseline run to this file")
    ap.add_argument("--reuse-baseline", action="store_true",
                    help="with --compare: load work/eval_baseline.pkl instead of re-running the baseline")
    ap.add_argument("--playback", action="store_true", help="play clips through the speakers and score the mic recording")
    ap.add_argument("--volumes", default="0.1,0.3,1.0")
    ap.add_argument("--per-class", type=int, default=2)
    args = ap.parse_args()

    def make(kind):
        p = DetectorParams.baseline() if kind == "baseline" else DetectorParams.default()
        if kind != "baseline":
            for kv in args.set:
                k, v = kv.split("=", 1)
                cur = getattr(p, k)
                setattr(p, k, type(cur)(v) if not isinstance(cur, bool) else v.lower() in ("1", "true", "yes"))
        return p

    WORK_DIR.mkdir(exist_ok=True)
    if args.playback:
        return playback(make(args.params), args)
    if args.compare:
        pkl = WORK_DIR / "eval_baseline.pkl"
        if args.reuse_baseline and pkl.exists():
            base = Loaded(pkl); print(f"  [baseline] loaded from {pkl}")
        else:
            base = Eval(DetectorParams.baseline(), args, "baseline").run()
        new_tag = args.tag or "default"
        new = Eval(make("default"), args, new_tag).run()
        for e in (base, new):
            if isinstance(e, Eval):
                (WORK_DIR / f"eval_{e.tag}.md").write_text(e.report())
        if args.write_suggested:
            write_thresholds(Path(args.write_suggested), new.R)
        text, ok = compare(base, new)
        out = WORK_DIR / f"eval_compare_{new_tag}.md"
        out.write_text(text)
        print(text); print(f"-> {out}  (full reports: work/eval_baseline.md, work/eval_{new_tag}.md)")
        sys.exit(0 if ok else 1)
    tag = args.tag or args.params
    e = Eval(make(args.params), args, tag).run()
    if args.write_suggested:
        write_thresholds(Path(args.write_suggested), e.R)
    out = WORK_DIR / f"eval_{tag}.md"
    out.write_text(e.report())
    print(e.report()); print(f"-> {out}")


if __name__ == "__main__":
    main()
