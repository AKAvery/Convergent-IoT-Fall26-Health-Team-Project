// ima_adpcm.cpp — see ima_adpcm.h. Same arithmetic, line for line, as ml/adpcm.py.
#include "ima_adpcm.h"

namespace adpcm {
namespace {

const int8_t INDEX_TABLE[16] = {-1, -1, -1, -1, 2, 4, 6, 8,
                                -1, -1, -1, -1, 2, 4, 6, 8};

const int16_t STEP_TABLE[89] = {
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767};

// Apply one code's step to the state. Shared by the encoder and decoder so they can't drift apart.
inline void advance(uint8_t code, int32_t vpdiff, State& s) {
  int32_t pred = s.predictor;
  if (code & 8) {
    pred -= vpdiff;
    if (pred < -32768) pred = -32768;
  } else {
    pred += vpdiff;
    if (pred > 32767) pred = 32767;
  }
  s.predictor = (int16_t)pred;
  int32_t index = (int32_t)s.index + INDEX_TABLE[code];
  if (index < 0) index = 0;
  else if (index > 88) index = 88;
  s.index = (uint8_t)index;
}

inline void packState(const State& s, uint8_t out[STATE_BYTES]) {
  uint16_t p = (uint16_t)s.predictor;
  out[0] = p & 0xFF;
  out[1] = p >> 8;
  out[2] = s.index;
  out[3] = 0;
}

}  // namespace

uint8_t encodeSample(int16_t x, State& s) {
  int32_t step = STEP_TABLE[s.index];
  int32_t diff = (int32_t)x - s.predictor;
  uint8_t code = 0;
  if (diff < 0) {
    code = 8;
    diff = -diff;
  }
  // Build vpdiff by successive halving, exactly like the decoder (not by multiplication).
  int32_t vpdiff = step >> 3;
  if (diff >= step) { code |= 4; diff -= step; vpdiff += step; }
  step >>= 1;
  if (diff >= step) { code |= 2; diff -= step; vpdiff += step; }
  step >>= 1;
  if (diff >= step) { code |= 1; vpdiff += step; }
  advance(code, vpdiff, s);
  return code;
}

int16_t decodeSample(uint8_t code, State& s) {
  int32_t step = STEP_TABLE[s.index];
  int32_t vpdiff = step >> 3;
  if (code & 4) vpdiff += step;
  if (code & 2) vpdiff += step >> 1;
  if (code & 1) vpdiff += step >> 2;
  advance(code & 0x0F, vpdiff, s);
  return s.predictor;
}

void encodePayload(const int16_t samples[SAMPLES_PER_PACKET], State& s, uint8_t out[PAYLOAD_BYTES]) {
  packState(s, out);                       // snapshot BEFORE the first sample
  uint8_t* codes = out + STATE_BYTES;
  for (size_t k = 0; k < CODE_BYTES; k++) {
    uint8_t lo = encodeSample(samples[2 * k], s);
    uint8_t hi = encodeSample(samples[2 * k + 1], s);
    codes[k] = lo | (hi << 4);             // low nibble first
  }
}

bool decodePayload(const uint8_t in[PAYLOAD_BYTES], int16_t out[SAMPLES_PER_PACKET]) {
  State s;
  s.predictor = (int16_t)(uint16_t)(in[0] | (in[1] << 8));
  if (in[2] > 88) return false;
  s.index = in[2];
  const uint8_t* codes = in + STATE_BYTES;
  for (size_t k = 0; k < CODE_BYTES; k++) {
    out[2 * k] = decodeSample(codes[k] & 0x0F, s);
    out[2 * k + 1] = decodeSample(codes[k] >> 4, s);
  }
  return true;
}

void encodeBlePacket(uint16_t seq, uint8_t flags, const int16_t samples[SAMPLES_PER_PACKET], State& s,
                     uint8_t out[BLE_PACKET_BYTES]) {
  for (size_t i = 0; i < SAMPLES_PER_PACKET; i++) {
    if (samples[i] == 32767 || samples[i] == -32768) {
      flags |= FLAG_CLIPPED;
      break;
    }
  }
  out[0] = seq & 0xFF;
  out[1] = seq >> 8;
  out[2] = 0;                              // reserved
  out[3] = 0;
  out[4] = flags;
  encodePayload(samples, s, out + BLE_HEADER_BYTES);
}

}  // namespace adpcm
