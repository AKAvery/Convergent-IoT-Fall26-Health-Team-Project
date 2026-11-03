// mic_dsp.h: what happens to each mic sample between I2S and int16, in plain C++ (no Arduino) so
// the native tests run it too (test/test_mic_dsp). Integer only: the ESP32-C3 has no FPU.
//
//   raw 24-bit -> fixed gain -> DcBlock -> Limiter (10 ms look-ahead) -> int16
//
// Why the limiter: int16 full scale is the mic's own full scale, and removing the DC offset moves
// loud waveforms off-centre. Measured on the front box (2026-11-03, "hello" at 2-3 cm): only 11
// raw samples came within 0.1% of the mic's rail, but after the DC blocker 535 samples overshot
// int16 by up to +5.2 dB and were hard-clipped, which is the popping. The limiter turns the gain
// down smoothly just before such a peak instead. Below the ceiling it is exactly unity, so normal
// audio is bit-identical to plain `y >> 8`, only one chunk (10 ms) later.
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace micdsp {

constexpr size_t CHUNK = 160;                         // samples per step: one I2S DMA buffer, 10 ms
constexpr int32_t RAIL_24 = 8388607;                  // the mic's 24-bit full scale
constexpr int32_t OVERLOAD_24 = RAIL_24 - RAIL_24 / 1000;   // within 0.1% of the rail = mic overload
constexpr int32_t CEILING_24 = 32000 << 8;            // limiter ceiling, -0.21 dBFS of int16
constexpr int32_t GAIN_ONE = 1 << 16;                 // limiter gains are Q16

// y[n] = x[n] - x[n-1] + R*y[n-1], R = 1 - 1/256 (-3 dB at ~10 Hz at 16 kHz), 8 fractional bits
// of state. The INMP441's DC offset drifts at 1-2 Hz and was ~33 dB above the sound. Output is not
// clamped: it can exceed the input range, the limiter handles that.
struct DcBlock {
  int32_t x1 = 0;
  int64_t acc = 0;   // y * 256
  int32_t step(int32_t x) {
    acc += ((int64_t)(x - x1) << 8) - (acc >> 8);
    x1 = x;
    return (int32_t)(acc >> 8);
  }
};

// Look-ahead peak limiter on whole chunks. Chunk k is output when chunk k+1 arrives, with a gain
// that ramps linearly across the chunk from g[k-1] to g[k], where
//   g[k] = min(1, C / peak[k], C / peak[k+1], 2 * g[k-1])
// Both ends of the ramp are <= C / peak[k] (g[k-1] already looked ahead at chunk k), so no sample
// of chunk k can exceed the ceiling C, and the gain never jumps. Recovery is at most 2x (6 dB) per
// chunk so it does not pump.
class Limiter {
 public:
  // Takes one chunk of filtered samples (24-bit scale, may exceed full scale) and writes the
  // previous chunk to `out` as int16. Returns true if that output chunk was turned down.
  bool process(const int32_t* in, int16_t* out) {
    int32_t peak = 0;
    for (size_t i = 0; i < CHUNK; i++) {
      int32_t a = in[i] < 0 ? -in[i] : in[i];
      if (a > peak) peak = a;
    }
    int32_t g = min(target(pendPeak_), target(peak));
    g = min(g, gPrev_ >= GAIN_ONE / 2 ? GAIN_ONE : 2 * gPrev_);
    const int64_t d = (int64_t)g - gPrev_;
    for (size_t i = 0; i < CHUNK; i++) {
      // C++ integer division truncates toward zero, so gi stays between gPrev_ and g.
      int32_t gi = gPrev_ + (int32_t)(d * (int64_t)(i + 1) / (int64_t)CHUNK);
      int32_t s = (int32_t)((((int64_t)pend_[i] * gi) >> 16) >> 8);
      if (s > 32767) s = 32767;       // unreachable (|s| <= 32001), kept as a guard
      if (s < -32768) s = -32768;
      out[i] = (int16_t)s;
    }
    const bool limited = g < GAIN_ONE || gPrev_ < GAIN_ONE;
    gPrev_ = g;
    for (size_t i = 0; i < CHUNK; i++) pend_[i] = in[i];
    pendPeak_ = peak;
    return limited;
  }

  int32_t gain() const { return gPrev_; }   // Q16 gain at the end of the last output chunk

 private:
  static int32_t min(int32_t a, int32_t b) { return a < b ? a : b; }
  static int32_t target(int32_t peak) {
    return peak <= CEILING_24 ? GAIN_ONE : (int32_t)(((int64_t)CEILING_24 << 16) / peak);
  }

  int32_t pend_[CHUNK] = {};
  int32_t pendPeak_ = 0;
  int32_t gPrev_ = GAIN_ONE;
};

}  // namespace micdsp
