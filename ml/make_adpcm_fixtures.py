#!/usr/bin/env python3
"""
Write the IMA ADPCM test vectors to fixtures/adpcm/ (repo root) with ml/adpcm.py as the reference.

    python3 make_adpcm_fixtures.py          # needs ml/data/ESC-50 for the two real-audio cases

Deterministic: re-running it reproduces the same bytes (the manifest records sha256 of every file).
The C++ encoder must reproduce <case>_packets.bin from <case>_input.bin; the Swift decoder must
reproduce <case>_decoded.bin from <case>_packets.bin. See fixtures/adpcm/README.md.
"""
import sys, json, hashlib
from pathlib import Path
import numpy as np
import soundfile as sf

ML_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ML_DIR))
import adpcm                                            # noqa: E402
from config import SAMPLE_RATE, ESC50_DIR               # noqa: E402
from audio_utils import load_mono_16k                   # noqa: E402

OUT = ML_DIR.parent / "fixtures" / "adpcm"
N = adpcm.SAMPLES_PER_PACKET
CLAP_CLIP = "1-104089-A-22.wav"      # ESC-50 "clapping"
DOG_CLIP = "1-100032-A-0.wav"        # ESC-50 "dog"


def loudest_second(path, peak_dbfs):
    """The loudest 1 s of an ESC-50 clip at 16 kHz, scaled to `peak_dbfs`, as int16."""
    y = load_mono_16k(path)
    e = np.convolve(y ** 2, np.ones(SAMPLE_RATE), mode="valid")
    s = int(np.argmax(e[::160]) * 160)
    seg = y[s:s + SAMPLE_RATE]
    seg = seg / np.abs(seg).max() * 10 ** (peak_dbfs / 20)
    return adpcm.float_to_int16(seg)


def sweep(n, f0=100.0, f1=7000.0, dbfs=-6.0):
    t = np.arange(n) / SAMPLE_RATE
    T = n / SAMPLE_RATE
    k = np.log(f1 / f0)
    phase = 2 * np.pi * f0 * T / k * (np.exp(t / T * k) - 1)
    return adpcm.float_to_int16(np.sin(phase) * 10 ** (dbfs / 20))


def cases():
    sr = SAMPLE_RATE
    t = np.arange(10 * N) / sr
    square = np.where(np.sin(2 * np.pi * 250 * t) >= 0, 32767, -32768).astype(np.int16)
    impulse = np.zeros(3 * N, dtype=np.int16)
    impulse[100] = 32767; impulse[101] = -32768; impulse[400] = 16384; impulse[700:704] = -32768
    c = [
        ("silence", "3 packets of digital zeros", np.zeros(3 * N, dtype=np.int16)),
        ("sine_1k", "1 kHz sine, -6 dBFS peak, 10 packets",
         adpcm.float_to_int16(np.sin(2 * np.pi * 1000 * t) * 10 ** (-6 / 20))),
        ("square_clipped", "250 Hz full-scale square (+32767 / -32768), 10 packets: slope overload + predictor clamp",
         square),
        ("impulse", "full-scale impulses (+32767, -32768, 16384, a 4-sample -32768 run) in silence, 3 packets",
         impulse),
    ]
    if (ESC50_DIR / "audio" / DOG_CLIP).exists():
        c.append(("esc50_dog", f"ESC-50 {DOG_CLIP} (dog), loudest 1 s, -3 dBFS peak, 50 packets",
                  loudest_second(ESC50_DIR / "audio" / DOG_CLIP, -3)))
        main = np.concatenate([sweep(sr), loudest_second(ESC50_DIR / "audio" / CLAP_CLIP, -3),
                               np.zeros(sr, dtype=np.int16)])
        c.append(("main", f"3 s: log sweep 100 Hz-7 kHz at -6 dBFS (1 s), ESC-50 {CLAP_CLIP} clap at -3 dBFS (1 s), "
                          "silence (1 s); 150 packets. Also written as input.wav / packets.bin / decoded.wav", main))
    else:
        print(f"!! {ESC50_DIR} missing: skipping the real-audio cases (run download_datasets.sh)")
    return c


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = {
        "codec": "IMA ADPCM 4-bit, 16 kHz mono int16",
        "nibble_order": "low nibble first: byte[k] = code[2k] | (code[2k+1] << 4)",
        "samples_per_packet": N,
        "packet_bytes": adpcm.BLE_PACKET_BYTES,
        "packet_layout": [
            {"offset": 0, "size": 2, "field": "seq", "type": "uint16 LE, 0 for the first packet of each case, +1 per packet"},
            {"offset": 2, "size": 2, "field": "reserved", "type": "uint16, always 0"},
            {"offset": 4, "size": 1, "field": "flags", "type": "uint8, bit0 = clipped (any input sample of the packet is -32768 or 32767)"},
            {"offset": 5, "size": 2, "field": "predictor", "type": "int16 LE, encoder state before the packet's first sample"},
            {"offset": 7, "size": 1, "field": "step_index", "type": "uint8 0..88, same moment"},
            {"offset": 8, "size": 1, "field": "pad", "type": "uint8, always 0"},
            {"offset": 9, "size": 160, "field": "codes", "type": "320 x 4-bit codes, low nibble first"},
        ],
        "initial_state": {"predictor": 0, "step_index": 0},
        "sample_format": "*.bin are raw little-endian int16 (input, decoded) or concatenated 169-byte packets",
        "cases": [],
    }
    for name, desc, x in cases():
        x = np.asarray(x, dtype=np.int16)
        assert len(x) % N == 0
        payloads = adpcm.encode(x)
        pk = bytearray()
        for i in range(len(x) // N):
            seg = x[i * N:(i + 1) * N]
            clipped = bool((seg == 32767).any() or (seg == -32768).any())
            pk += adpcm.ble_packet(i, payloads[i * adpcm.PAYLOAD_BYTES:(i + 1) * adpcm.PAYLOAD_BYTES], clipped)
        y = adpcm.decode(payloads)
        files = {"input": OUT / f"{name}_input.bin", "packets": OUT / f"{name}_packets.bin",
                 "decoded": OUT / f"{name}_decoded.bin"}
        files["input"].write_bytes(x.astype("<i2").tobytes())
        files["packets"].write_bytes(bytes(pk))
        files["decoded"].write_bytes(y.astype("<i2").tobytes())
        err = x.astype(np.float64) - y
        p_sig = float(np.mean(x.astype(np.float64) ** 2))
        p_err = float(np.mean(err ** 2))
        entry = {"name": name, "description": desc, "n_samples": int(len(x)), "n_packets": int(len(x) // N),
                 "files": {k: v.name for k, v in files.items()},
                 "sha256": {k: sha(v) for k, v in files.items()},
                 "max_abs_error": int(np.abs(err).max()),
                 "snr_db": round(10 * np.log10(p_sig / p_err), 2) if p_err > 0 and p_sig > 0 else None}
        if name == "main":
            for stem, data in (("input", x), ("decoded", y)):
                sf.write(OUT / f"{stem}.wav", data, SAMPLE_RATE, subtype="PCM_16")
            (OUT / "packets.bin").write_bytes(bytes(pk))
            entry["also"] = {"input_wav": "input.wav", "packets_bin": "packets.bin", "decoded_wav": "decoded.wav"}
        manifest["cases"].append(entry)
        print(f"{name:15s} {len(x):6d} samples {len(x) // N:4d} packets  max|err| {entry['max_abs_error']:6d}  "
              f"SNR {entry['snr_db']} dB")
    (OUT / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"-> {OUT}")


if __name__ == "__main__":
    main()
