#!/usr/bin/env python3
"""
Listen to one sound box from the Mac, the way the iPhone app will: no app needed.

    .venv/bin/python firmware/tools/box_listen.py                    # FRONT, 10 s of `level`
    .venv/bin/python firmware/tools/box_listen.py --pos BACK -s 30
    .venv/bin/python firmware/tools/box_listen.py --audio out.wav    # also stream audio, save a WAV

What it does:
  - finds SoundBox-<POS>, connects, subscribes to `level` and prints it once a second
    (peak dBFS with a bar, packets per second, seq gaps, clipped flag)
  - with --audio: subscribes to `audio`, writes control = 01, decodes every 169-byte packet
    with ml/adpcm.py (each packet on its own, as the phone will), writes control = 00 at the
    end and saves the decoded audio as a 16 kHz WAV you can play or run through the detector
  - prints a summary: packet rates, missed packets, MTU

Needs bleak + numpy (both in the repo's .venv). macOS asks once for Bluetooth permission for
the terminal app. Flash `box` for real mic data, or `ble_fake` for a fake `level` (no audio).
"""
import argparse, asyncio, struct, sys, time, wave
from pathlib import Path

import numpy as np
from bleak import BleakClient, BleakScanner

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "ml"))
import adpcm  # noqa: E402

LEVEL = "e89a434d-2aa6-4a70-ae89-a47761df7c97"
AUDIO = "a6c379f3-83f3-4927-be5c-ae2966376ec4"
CONTROL = "f2b50bb3-d6c1-46a0-b5cf-ff3b5a2396f0"
SAMPLE_RATE = 16000


def gaps(seqs):
    """Packets missing between consecutive seq numbers (uint16, wraps)."""
    return sum(((b - a) & 0xFFFF) - 1 for a, b in zip(seqs, seqs[1:]))


def bar(db, lo=-90.0, hi=0.0, width=30):
    n = int(round((min(max(db, lo), hi) - lo) / (hi - lo) * width))
    return "#" * n + "." * (width - n)


async def main(args):
    name = f"SoundBox-{args.pos.upper()}"
    print(f"scanning for {name} ...")
    dev = await BleakScanner.find_device_by_name(name, timeout=15)
    if dev is None:
        sys.exit(f"{name} not found. Is it powered, flashed with `box` or `ble_fake`, and not connected to a phone?")

    levels, audio_seqs, audio_chunks = [], [], []
    bad_audio = 0
    t_start = time.monotonic()

    def on_level(_, data):
        seq, peak, flags = struct.unpack("<HhB", bytes(data))
        levels.append((time.monotonic(), seq, peak / 10, flags))

    def on_audio(_, data):
        nonlocal bad_audio
        try:
            p = adpcm.parse_ble_packet(bytes(data))
            audio_chunks.append(adpcm.decode_packet(p["payload"]))
            audio_seqs.append(p["seq"])
        except ValueError:
            bad_audio += 1

    async with BleakClient(dev) as c:
        print(f"connected to {name} ({dev.address}), MTU {c.mtu_size}")
        if args.audio and c.mtu_size < adpcm.BLE_PACKET_BYTES + 3:
            print(f"!! MTU {c.mtu_size} < {adpcm.BLE_PACKET_BYTES + 3}: the box will not send audio")
        await c.start_notify(LEVEL, on_level)
        if args.audio:
            await c.start_notify(AUDIO, on_audio)
            await c.write_gatt_char(CONTROL, b"\x01", response=True)
            print("control = 01 (start audio)")

        shown = 0
        end = time.monotonic() + args.seconds
        while time.monotonic() < end:
            await asyncio.sleep(1.0)
            if len(levels) > shown:
                _, seq, db, flags = levels[-1]
                last_sec = [lv for lv in levels if lv[0] > time.monotonic() - 1.0]
                peak = max(lv[2] for lv in last_sec) if last_sec else db
                clip = " CLIPPED" if any(lv[3] & 1 for lv in last_sec) else ""
                extra = f" | audio {len(audio_seqs)} pkts" if args.audio else ""
                print(f"{time.monotonic() - t_start:5.1f}s  peak {peak:6.1f} dBFS  {bar(peak)}{clip}{extra}")
                shown = len(levels)
            else:
                print(f"{time.monotonic() - t_start:5.1f}s  (no level packets yet)")

        if args.audio:
            await c.write_gatt_char(CONTROL, b"\x00", response=True)
            print("control = 00 (stop audio)")
            await asyncio.sleep(0.2)
            await c.stop_notify(AUDIO)
        await c.stop_notify(LEVEL)

    print("\n--- summary ---")
    if len(levels) > 1:
        span = levels[-1][0] - levels[0][0]
        print(f"level: {len(levels)} packets, {(len(levels) - 1) / span:.1f} Hz (want 10), "
              f"missed {gaps([lv[1] for lv in levels])}")
    else:
        print("level: no packets received")
    if args.audio:
        n = len(audio_seqs)
        secs = n * adpcm.SAMPLES_PER_PACKET / SAMPLE_RATE
        missed = gaps(audio_seqs)
        print(f"audio: {n} packets = {secs:.1f} s of sound, missed {missed}"
              f"{f' ({100 * missed / (n + missed):.1f}%)' if n + missed else ''}, malformed {bad_audio}")
        if n:
            print(f"       about {n / args.seconds:.0f} packets/s (want 50), "
                  f"{n * adpcm.BLE_PACKET_BYTES * 8 / args.seconds / 1000:.0f} kbit/s")
            pcm = np.concatenate(audio_chunks).astype("<i2")
            out = Path(args.audio)
            with wave.open(str(out), "wb") as w:
                w.setnchannels(1)
                w.setsampwidth(2)
                w.setframerate(SAMPLE_RATE)
                w.writeframes(pcm.tobytes())
            peak = int(np.abs(pcm.astype(np.int32)).max())
            print(f"       saved {out} (peak {20 * np.log10(max(peak, 1) / 32768):.1f} dBFS). "
                  "Missed packets are left out, not filled with silence.")
        else:
            print("       no audio arrived: check the box's serial log (subscribed? MTU? `box` firmware?)")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--pos", default="FRONT", help="FRONT, BACK, LEFT or RIGHT (default FRONT)")
    ap.add_argument("-s", "--seconds", type=float, default=10.0, help="how long to listen (default 10)")
    ap.add_argument("--audio", metavar="OUT.wav", help="also stream audio and save it to this WAV file")
    asyncio.run(main(ap.parse_args()))
