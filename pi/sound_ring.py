#!/usr/bin/env python3
"""
sound_ring.py — Fortnite-style "visualize sound effects" for real life.

Hardware: Raspberry Pi + Seeed ReSpeaker 4-Mic Array HAT.
  - Reads 4 mic channels at 16 kHz
  - Estimates direction of arrival (GCC-PHAT on the two diagonal mic pairs)
  - Classifies the sound with YAMNet embeddings + our trained head (TFLite, see ../ml)
  - Lights the HAT's built-in 12-LED APA102 ring at the sound's direction,
    colored by sound type

Run:  python3 sound_ring.py
Stop: Ctrl-C
"""

import math
import time
import collections
import numpy as np
import sounddevice as sd
import spidev

try:
    import tflite_runtime.interpreter as tflite
except ImportError:  # fall back to full TensorFlow if installed
    import tensorflow.lite as tflite

# ---------------------------------------------------------------- settings --
SAMPLE_RATE = 16000
CHANNELS = 4
BLOCK_SECONDS = 0.5            # how often we update (YAMNet wants ~0.975 s windows; we overlap)
WINDOW_SECONDS = 1.0
DEVICE_NAME = "seeed-4mic"     # substring of the ALSA device name; run `python3 -m sounddevice` to check

SOUND_SPEED = 343.2
MIC_DISTANCE = 0.08127         # metres, between diagonally opposite mics on the 4-Mic HAT
MAX_TDOA = MIC_DISTANCE / SOUND_SPEED
CALIBRATION_OFFSET_DEG = 0     # clap from the HAT's "front" (USB side) and adjust until LED 0 lights

NUM_LEDS = 12
BRIGHTNESS = 10                # 1..31
LOUDNESS_GATE_DB = -45         # ignore anything quieter than this (dBFS); raise if it flickers on room noise
MIN_CONFIDENCE = 0.5

EMBED_MODEL_PATH = "yamnet_embedding_metadata.tflite"   # YAMNet backbone -> 1024-d embedding
HEAD_MODEL_PATH = "sound_head.tflite"                   # our trained head (see ../ml)
LABELS_PATH = "labels.json"
YAMNET_WINDOW = 15600                                   # 0.975 s @ 16 kHz, fixed by YAMNet

# Our label -> LED colour (R, G, B). Labels come from labels.json.
HIGHLIGHT = {
    "siren":        (255, 0, 0),
    "alarm":        (255, 0, 0),
    "car_horn":     (255, 60, 0),
    "glass_break":  (180, 0, 255),
    "dog":          (255, 160, 0),
    "cat":          (255, 160, 0),
    "baby_cry":     (255, 100, 200),
    "knock":        (0, 200, 255),
    "clap":         (255, 255, 255),
    "footsteps":    (255, 255, 0),
    "speech":       (0, 255, 80),
    "appliance":    (0, 80, 255),
}
IGNORE = {"other"}

# -------------------------------------------------------------- LED driver --
class APA102Ring:
    """Minimal APA102 driver for the 12 LEDs on the ReSpeaker 4-Mic HAT (SPI0)."""

    def __init__(self, n=NUM_LEDS, brightness=BRIGHTNESS):
        self.n = n
        self.brightness = max(1, min(31, brightness))
        self.spi = spidev.SpiDev()
        self.spi.open(0, 1)
        self.spi.max_speed_hz = 8_000_000
        self.pixels = [(0, 0, 0)] * n
        self.show()

    def set(self, i, rgb):
        self.pixels[i % self.n] = rgb

    def clear(self):
        self.pixels = [(0, 0, 0)] * self.n

    def show(self):
        frame = [0x00] * 4
        for r, g, b in self.pixels:
            frame += [0xE0 | self.brightness, b, g, r]
        frame += [0xFF] * ((self.n + 15) // 16 + 1)
        self.spi.xfer2(frame)

    def point(self, angle_deg, rgb, spread=1):
        """Light the LED nearest `angle_deg` (0 = front, clockwise), with dim neighbours."""
        self.clear()
        centre = int(round(angle_deg / 360 * self.n)) % self.n
        for k in range(-spread, spread + 1):
            fade = 1.0 if k == 0 else 0.25
            self.set(centre + k, tuple(int(c * fade) for c in rgb))
        self.show()

    def close(self):
        self.clear()
        self.show()
        self.spi.close()

# ---------------------------------------------------------- direction (DOA) --
def gcc_phat(sig, ref, fs=SAMPLE_RATE, max_tau=MAX_TDOA, interp=16):
    """Return time delay (s) of `sig` relative to `ref` using GCC-PHAT."""
    n = sig.shape[0] + ref.shape[0]
    SIG = np.fft.rfft(sig, n=n)
    REF = np.fft.rfft(ref, n=n)
    R = SIG * np.conj(REF)
    cc = np.fft.irfft(R / (np.abs(R) + 1e-12), n=interp * n)
    max_shift = int(interp * n / 2)
    if max_tau:
        max_shift = min(int(interp * fs * max_tau), max_shift)
    cc = np.concatenate((cc[-max_shift:], cc[:max_shift + 1]))
    shift = np.argmax(np.abs(cc)) - max_shift
    return shift / float(interp * fs)

def estimate_angle(block):
    """block: (N, 4). Mics 0-2 and 1-3 are diagonal pairs on the 4-Mic HAT."""
    tau02 = gcc_phat(block[:, 0], block[:, 2])
    tau13 = gcc_phat(block[:, 1], block[:, 3])
    # Each diagonal pair gives a component of the arrival vector along that diagonal.
    x = np.clip(tau02 / MAX_TDOA, -1, 1)
    y = np.clip(tau13 / MAX_TDOA, -1, 1)
    angle = math.degrees(math.atan2(y, x))
    angle = (angle + 45 + CALIBRATION_OFFSET_DEG) % 360   # diagonals are 45° off the board axes
    return angle

# ----------------------------------------------------------------- YAMNet --
class SoundClassifier:
    """YAMNet embedding backbone + our small trained head."""

    def __init__(self):
        import json
        self.embed = tflite.Interpreter(model_path=EMBED_MODEL_PATH, num_threads=4)
        self.embed.allocate_tensors()
        self.e_in = self.embed.get_input_details()[0]["index"]
        self.e_out = self.embed.get_output_details()[0]["index"]
        self.head = tflite.Interpreter(model_path=HEAD_MODEL_PATH)
        self.head.allocate_tensors()
        self.h_in = self.head.get_input_details()[0]["index"]
        self.h_out = self.head.get_output_details()[0]["index"]
        with open(LABELS_PATH) as f:
            self.names = json.load(f)

    def classify(self, mono):
        mono = mono.astype(np.float32)
        peak = np.abs(mono).max()
        if peak > 0:
            mono = mono / peak * 0.5          # same normalisation as training
        # average predictions over 0.975 s windows covering the buffer
        probs = []
        starts = range(0, max(1, len(mono) - YAMNET_WINDOW + 1), YAMNET_WINDOW // 2)
        for s in starts:
            w = mono[s:s + YAMNET_WINDOW]
            if len(w) < YAMNET_WINDOW:
                w = np.pad(w, (0, YAMNET_WINDOW - len(w)))
            self.embed.set_tensor(self.e_in, w[np.newaxis, :])
            self.embed.invoke()
            emb = self.embed.get_tensor(self.e_out)
            self.head.set_tensor(self.h_in, emb)
            self.head.invoke()
            probs.append(self.head.get_tensor(self.h_out)[0])
        mean = np.mean(probs, axis=0)
        top = np.argsort(mean)[::-1][:3]
        return [(self.names[i], float(mean[i])) for i in top]

def colour_for(name):
    for key, rgb in HIGHLIGHT.items():
        if key.lower() in name.lower():
            return rgb
    return (40, 40, 40)

# ------------------------------------------------------------------- main --
def main():
    ring = APA102Ring()
    net = SoundClassifier()
    buf = collections.deque(maxlen=int(WINDOW_SECONDS * SAMPLE_RATE))
    block_frames = int(BLOCK_SECONDS * SAMPLE_RATE)

    print("Listening. Ctrl-C to stop.")
    with sd.InputStream(device=DEVICE_NAME, channels=CHANNELS, samplerate=SAMPLE_RATE,
                        dtype="float32", blocksize=block_frames) as stream:
        try:
            while True:
                block, _ = stream.read(block_frames)
                buf.extend(block)
                if len(buf) < buf.maxlen:
                    continue
                window = np.array(buf)

                rms = np.sqrt(np.mean(window[:, 0] ** 2))
                level_db = 20 * math.log10(rms + 1e-9)
                if level_db < LOUDNESS_GATE_DB:
                    ring.clear(); ring.show()
                    continue

                angle = estimate_angle(block)
                top = net.classify(window.mean(axis=1))
                name, conf = top[0]
                if name in IGNORE or conf < MIN_CONFIDENCE:
                    ring.clear(); ring.show()
                    continue

                print(f"{name:25s} {conf:4.2f}  {angle:5.0f}°  {level_db:5.1f} dB   | {top[1][0]}, {top[2][0]}")
                ring.point(angle, colour_for(name))
        except KeyboardInterrupt:
            pass
        finally:
            ring.close()

if __name__ == "__main__":
    main()
