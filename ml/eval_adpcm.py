#!/usr/bin/env python3
"""
Does the classifier survive IMA ADPCM? (week-1 task A2)

Runs eval_pipeline.py's full evaluation twice in one process with the same seeds, models and clips:
  ref     the default pipeline, unchanged (float audio straight into the detector)
  adpcm   the same, but every stream the detector sees is first rounded to int16 and passed through
          ml/adpcm.py encode -> decode (the whole stream incl. the 2 s background pads, encoder
          starting from state (0, 0) like a box that just got control = 1)

The codec is applied by wrapping eval_pipeline.run_stream, so it reaches every scenario (confusion,
level sweep, false fires, OOV, overlap, threshold replay). eval_pipeline.py itself is not modified.

    python3 eval_adpcm.py            # full run (~2x the default eval), -> work/eval_adpcm.md
    python3 eval_adpcm.py --quick    # smoke test

Writes work/eval_adpcm.md (comparison; the hand-written notes/verdict appended below it are lost on re-run), work/eval_adpcm_ref_full.md and
work/eval_adpcm_full.md (full reports), and the harness's own work/eval_adpcm_ref.pkl / eval_adpcm.pkl.
Exit code 1 if the A2 decision rule says "propose another codec".
"""
import sys, argparse
from pathlib import Path
import numpy as np

ML_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ML_DIR))
import eval_pipeline as ep                               # noqa: E402
import adpcm                                             # noqa: E402

SAFETY = ["siren", "alarm", "car_horn", "glass_break"]   # docs/week1-tasks.md A2
MAX_SAFETY_CAUGHT_DROP = 0.05
MAX_BIG_ACC_DROP = 0.02

_orig_run_stream = ep.run_stream


def adpcm_run_stream(det, audio, keep_probs=False):
    return _orig_run_stream(det, adpcm.roundtrip_float(audio), keep_probs)


def big_acc(per, labs):
    bn = sum(s["big_n"] for l in labs for s in per[l]); bo = sum(s["big_ok"] for l in labs for s in per[l])
    return bo / bn if bn else float("nan")


def mean(xs):
    return float(np.mean(xs)) if len(xs) else float("nan")


def report(ref, new, harness_cmp):
    t = ref.targets
    L = ["# Does the classifier survive IMA ADPCM?\n",
         "Same pipeline, same clips, same seeds, run back to back in one process: **ref** = default eval "
         "(float audio), **adpcm** = every detector stream rounded to int16 and passed through `ml/adpcm.py` "
         "encode -> decode (4-bit IMA, 320-sample packets). Produced by `ml/eval_adpcm.py`.\n",
         f"params: `{new.params.describe()}`  ",
         f"test split: {sum(len(v) for v in new.by_label.values())} clips{' (QUICK subset)' if new.args.quick else ''}\n"]

    # -- decision rule ---------------------------------------------------------------
    cr, cn = ref.R["confusion"], new.R["confusion"]
    fails = []
    for c in SAFETY:
        if c not in t: continue
        a, b = mean([s["caught"] for s in cr[c]]), mean([s["caught"] for s in cn[c]])
        if b < a - MAX_SAFETY_CAUGHT_DROP:
            fails.append(f"{c} caught {a:.2f} -> {b:.2f} at -20 dBFS")
        for lv in sorted(new.R["levels"]):
            a = mean([s["caught"] for s in ref.R["levels"][lv][c]]); b = mean([s["caught"] for s in new.R["levels"][lv][c]])
            if b < a - MAX_SAFETY_CAUGHT_DROP and lv != ep.REF_LEVEL_DB:
                fails.append(f"{c} caught {a:.2f} -> {b:.2f} at {lv} dBFS")
    ba, bb = big_acc(cr, t), big_acc(cn, t)
    if bb < ba - MAX_BIG_ACC_DROP:
        fails.append(f"big-label accuracy {ba:.3f} -> {bb:.3f}")
    L.append("## Decision rule (docs/week1-tasks.md A2)\n")
    L.append(f"Propose another codec if any safety class ({', '.join(SAFETY)}) loses more than "
             f"{MAX_SAFETY_CAUGHT_DROP:.2f} caught (checked at -20 dBFS and every level of the sweep) or big-label "
             f"accuracy drops more than {MAX_BIG_ACC_DROP * 100:.0f} points.\n")
    L.append(f"- big-label accuracy (pooled over target clips at -20 dBFS): **{ba:.3f} -> {bb:.3f}** "
             f"({(bb - ba) * 100:+.1f} points)")
    L.append("- result: " + ("**FAILED**: " + "; ".join(fails) if fails else "**passed**, no safety class lost more "
             f"than {MAX_SAFETY_CAUGHT_DROP:.2f} caught at any level") + "\n")

    # -- per class at -20 dBFS ---------------------------------------------------------
    L.append("## Per class at -20 dBFS (ref -> adpcm)\n")
    L.append("| class | n | caught | wrong label | wrong shown big | big-label acc | onset median s |")
    L.append("|---|---|---|---|---|---|---|")
    for c in t:
        if not cr[c]: continue
        def f(per):
            ons = [s["onset"] for s in per[c] if s["onset"] is not None]
            return (mean([s["caught"] for s in per[c]]), mean([bool(s["wrong"]) for s in per[c]]),
                    mean([bool(s["wrong_big"]) for s in per[c]]), big_acc(per, [c]),
                    float(np.median(ons)) if ons else float("nan"))
        a, b = f(cr), f(cn)
        mark = " **(safety)**" if c in SAFETY else ""
        L.append(f"| {c}{mark} | {len(cr[c])} | " + " | ".join(
            f"{x:.2f} -> {y:.2f}" + (" ⚠" if k == 0 and y < x - MAX_SAFETY_CAUGHT_DROP else "")
            for k, (x, y) in enumerate(zip(a, b))) + " |")
    L.append(f"| **mean** | | {mean([mean([s['caught'] for s in cr[c]]) for c in t if cr[c]]):.2f} -> "
             f"{mean([mean([s['caught'] for s in cn[c]]) for c in t if cn[c]]):.2f} | "
             f"{mean([mean([bool(s['wrong']) for s in cr[c]]) for c in t if cr[c]]):.2f} -> "
             f"{mean([mean([bool(s['wrong']) for s in cn[c]]) for c in t if cn[c]]):.2f} | | {ba:.2f} -> {bb:.2f} | |")
    if cr.get(ep.OTHER_LABEL):
        L.append(f"\n'other' test clips with any target fired: {mean([bool(s['wrong']) for s in cr[ep.OTHER_LABEL]]):.2f} -> "
                 f"{mean([bool(s['wrong']) for s in cn[ep.OTHER_LABEL]]):.2f}\n")

    # -- level sweep per class -----------------------------------------------------------
    levels = sorted(new.R["levels"], reverse=True)
    for key, title in (("caught", "Caught rate"), ("wrong", "Wrong-label rate")):
        L.append(f"## Level sweep: {title.lower()} per class (ref -> adpcm)\n")
        L.append("| class | " + " | ".join(f"{lv} dB" for lv in levels) + " |")
        L.append("|---|" + "---|" * len(levels))
        get = (lambda s: s["caught"]) if key == "caught" else (lambda s: bool(s["wrong"]))
        for c in t + ["**mean**"]:
            cells = []
            for lv in levels:
                labs = t if c == "**mean**" else [c]
                a = mean([get(s) for l in labs for s in ref.R["levels"][lv][l]])
                b = mean([get(s) for l in labs for s in new.R["levels"][lv][l]])
                flag = " ⚠" if key == "caught" and c in SAFETY and b < a - MAX_SAFETY_CAUGHT_DROP else ""
                cells.append(f"{a:.2f} -> {b:.2f}{flag}")
            L.append(f"| {c}{' (safety)' if c in SAFETY else ''} | " + " | ".join(cells) + " |")
        L.append("")

    L.append("## eval_pipeline.compare(ref, adpcm): false fires, overlap, OOV, regression guard\n")
    L.append("\n".join(harness_cmp.splitlines()[3:]))     # drop its title/params lines
    return "\n".join(L) + "\n", not fails


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--demand", action="store_true")
    ap.add_argument("--model-dir", default=str(ML_DIR.parent / "pi"))
    ap.add_argument("--out", default=str(ep.WORK_DIR / "eval_adpcm.md"))
    a = ap.parse_args()
    args = argparse.Namespace(quick=a.quick, demand=a.demand, model_dir=a.model_dir, thresholds=None)
    ep.WORK_DIR.mkdir(exist_ok=True)
    sfx = "_quick" if a.quick else ""

    ep.run_stream = _orig_run_stream
    ref = ep.Eval(ep.DetectorParams.default(), args, f"adpcm_ref{sfx}").run()
    (ep.WORK_DIR / f"eval_adpcm_ref{sfx}_full.md").write_text(ref.report())

    ep.run_stream = adpcm_run_stream
    try:
        new = ep.Eval(ep.DetectorParams.default(), args, f"adpcm{sfx}").run()
    finally:
        ep.run_stream = _orig_run_stream
    (ep.WORK_DIR / f"eval_adpcm{sfx}_full.md").write_text(new.report())

    harness_text, guard_ok = ep.compare(ref, new)
    text, ok = report(ref, new, harness_text)
    out = Path(a.out) if not a.quick else ep.WORK_DIR / "eval_adpcm_quick.md"
    out.write_text(text)
    print(text); print(f"-> {out}  (harness regression guard: {'passed' if guard_ok else 'FAILED'})")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
