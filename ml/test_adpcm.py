#!/usr/bin/env python3
"""
Tests for ml/adpcm.py against fixtures/adpcm/. Plain asserts; runs with pytest or on its own:

    python3 test_adpcm.py
"""
import sys, json, hashlib, struct, warnings
from pathlib import Path
import numpy as np

ML_DIR = Path(__file__).resolve().parent
sys.path.insert(0, str(ML_DIR))
import adpcm                                            # noqa: E402

FIX = ML_DIR.parent / "fixtures" / "adpcm"
MANIFEST = json.loads((FIX / "manifest.json").read_text())
CASES = {c["name"]: c for c in MANIFEST["cases"]}


def load(case, kind):
    data = (FIX / case["files"][kind]).read_bytes()
    return data if kind == "packets" else np.frombuffer(data, dtype="<i2").astype(np.int16)


def payloads_of(packets):
    n = adpcm.BLE_PACKET_BYTES
    return [adpcm.parse_ble_packet(packets[i:i + n]) for i in range(0, len(packets), n)]


def test_files_match_manifest():
    for c in CASES.values():
        for kind, name in c["files"].items():
            assert hashlib.sha256((FIX / name).read_bytes()).hexdigest() == c["sha256"][kind], (c["name"], kind)


def test_encode_reproduces_packets_byte_for_byte():
    for c in CASES.values():
        x = load(c, "input")
        pk = load(c, "packets")
        assert len(pk) == c["n_packets"] * 169
        assert b"".join(p["payload"] for p in payloads_of(pk)) == adpcm.encode(x), c["name"]
        for i, p in enumerate(payloads_of(pk)):
            assert p["seq"] == i
            assert pk[i * 169 + 2:i * 169 + 4] == b"\0\0"          # reserved
            assert p["payload"][3] == 0                            # pad


def test_decode_reproduces_decoded_sample_for_sample():
    for c in CASES.values():
        y = adpcm.decode(b"".join(p["payload"] for p in payloads_of(load(c, "packets"))))
        assert np.array_equal(y, load(c, "decoded")), c["name"]


def test_each_packet_decodes_on_its_own():
    """A packet decoded alone (from its header state) equals the same slice of a continuous decode."""
    for c in CASES.values():
        x = load(c, "input")
        codes, _ = adpcm.encode_codes(x)
        continuous, _ = adpcm.decode_codes(codes)
        for i, p in enumerate(payloads_of(load(c, "packets"))):
            alone = adpcm.decode_packet(p["payload"])
            assert np.array_equal(alone, continuous[i * 320:(i + 1) * 320]), (c["name"], i)


def test_header_and_nibble_order():
    # hand-checked: 2 samples from state (0, 0); step 7.
    # x=+20: diff 20 >= 7 -> 4, 13 >= 3 -> 2, 10 >= 1 -> 1: code 7, vpdiff 0+7+3+1 = 11, pred 11, index 8 (step 16)
    # x=-20: diff -31 -> sign; 31 >= 16 -> 4, 15 >= 8 -> 2, 7 >= 4 -> 1: code 15, vpdiff 2+16+8+4 = 30, pred -19
    codes, st = adpcm.encode_codes([20, -20])
    assert codes == [7, 15] and st == (-19, 16)
    assert adpcm.pack_nibbles(codes) == bytes([0xF7])             # low nibble = first sample
    payload, _ = adpcm.encode_packet(np.zeros(320, np.int16), (-1234, 42))
    assert payload[:4] == struct.pack("<hBB", -1234, 42, 0) == bytes([0x2E, 0xFB, 42, 0])
    assert adpcm.unpack_state(payload) == (-1234, 42)


def test_matches_independent_reference():
    """CPython's audioop (the IMA reference arithmetic, high nibble first) must give the same codes."""
    with warnings.catch_warnings():
        warnings.simplefilter("ignore", DeprecationWarning)
        try:
            import audioop
        except ImportError:
            print("  (audioop not available on this Python; skipping the independent cross-check)")
            return
    for c in CASES.values():
        x = load(c, "input")
        ref, _ = audioop.lin2adpcm(x.astype("<i2").tobytes(), 2, None)
        swapped = bytes(((b & 0x0F) << 4) | (b >> 4) for b in ref)
        codes, _ = adpcm.encode_codes(x)
        assert adpcm.pack_nibbles(codes) == swapped, c["name"]
        ref_dec, _ = audioop.adpcm2lin(ref, 2, None)
        assert np.array_equal(np.frombuffer(ref_dec, dtype="<i2"), load(c, "decoded")), c["name"]


def test_error_within_normal_adpcm_bounds():
    """Per sample: whenever the quantiser is not saturated (|code| < 7) and the predictor did not clamp,
    |x - decoded| <= step/2 + 1, the IMA quantiser's resolution. Per signal: after 20 ms of step
    adaptation, SNR >= 20 dB on signals ADPCM can track (sine, sweep + clap, real dog clip)."""
    for c in CASES.values():
        x = load(c, "input").astype(np.int64)
        codes, _ = adpcm.encode_codes(x)
        y, _ = adpcm.decode_codes(codes)
        y = y.astype(np.int64)
        index = 0
        for xi, ci, yi in zip(x.tolist(), codes, y.tolist()):
            step = adpcm.STEP_TABLE[index]
            if (ci & 7) != 7 and -32768 < yi < 32767:
                assert abs(xi - yi) <= (step >> 1) + 1, (c["name"], xi, yi, step)
            index = min(88, max(0, index + adpcm.INDEX_TABLE[ci]))
    for name in ("sine_1k", "main", "esc50_dog"):
        if name not in CASES: continue
        x = load(CASES[name], "input").astype(np.float64)[320:]
        y = load(CASES[name], "decoded").astype(np.float64)[320:]
        nz = np.abs(x) > 0
        snr = 10 * np.log10(np.sum(x[nz] ** 2) / np.sum((x - y)[nz] ** 2))
        assert snr >= 20, (name, snr)
    assert not load(CASES["silence"], "decoded").any()


def test_random_roundtrip_and_float_helper():
    rng = np.random.default_rng(7)
    x = (np.cumsum(rng.standard_normal(320 * 25)) * 200).clip(-32768, 32767).astype(np.int16)  # brown noise
    y = adpcm.decode(adpcm.encode(x))
    assert len(y) == len(x)
    e = x[320:].astype(float) - y[320:]
    assert 10 * np.log10(np.mean(x[320:].astype(float) ** 2) / np.mean(e ** 2)) >= 20
    yf = adpcm.roundtrip_float(x.astype(np.float32) / 32768)
    assert np.array_equal(adpcm.float_to_int16(yf), y)
    odd = adpcm.decode(adpcm.encode(x[:1000]))                 # partial last packet is zero-padded
    assert len(odd) == 1280 and np.array_equal(odd[:1000], y[:1000])


if __name__ == "__main__":
    tests = [(k, v) for k, v in sorted(globals().items()) if k.startswith("test_") and callable(v)]
    for name, fn in tests:
        fn(); print(f"ok  {name}")
    print(f"{len(tests)} passed")
