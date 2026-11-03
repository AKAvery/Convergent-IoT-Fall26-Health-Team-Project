// mic_dsp.h on the Mac, no board needed:
//
//   pio test -e native
//
// The limiter's promises: exactly unity below the ceiling (normal audio is bit-identical to plain
// `y >> 8`, one chunk later), nothing ever reaches the int16 rails, and it lets go after a peak.
#include <unity.h>

#include <stdint.h>

#include "mic_dsp.h"

using namespace micdsp;

static uint32_t rng = 12345;
static int32_t randIn(int32_t limit) {   // uniform in [-limit, limit]
  rng = rng * 1664525u + 1013904223u;
  return (int32_t)((int64_t)(rng >> 1) % (2 * (int64_t)limit + 1) - limit);
}

void setUp() {}
void tearDown() {}

void test_dc_block_removes_offset() {
  DcBlock dc;
  int32_t y = 0;
  for (int i = 0; i < 8000; i++) y = dc.step(2000000);   // 0.5 s of a constant 24% offset
  TEST_ASSERT_INT32_WITHIN(256, 0, y);                     // under 1 LSB of int16
}

void test_limiter_is_exact_below_ceiling() {
  Limiter lim;
  int32_t prev[CHUNK] = {};
  int32_t in[CHUNK];
  int16_t out[CHUNK];
  for (int k = 0; k < 200; k++) {
    for (size_t i = 0; i < CHUNK; i++) in[i] = randIn(CEILING_24);
    TEST_ASSERT_FALSE(lim.process(in, out));
    for (size_t i = 0; i < CHUNK; i++) TEST_ASSERT_EQUAL_INT16((int16_t)(prev[i] >> 8), out[i]);
    for (size_t i = 0; i < CHUNK; i++) prev[i] = in[i];
  }
}

void test_limiter_never_reaches_rails() {
  Limiter lim;
  int32_t in[CHUNK];
  int16_t out[CHUNK];
  int limitedChunks = 0;
  for (int k = 0; k < 5000; k++) {
    // Mostly normal audio, sometimes bursts far past full scale (up to 2^29, i.e. +36 dB with
    // MIC_GAIN_BITS = 6), with the peak sample anywhere in the chunk including its edges.
    int32_t amp = (k % 7 == 0) ? (int32_t)(1 << 29) : (k % 3 == 0) ? RAIL_24 * 2 : CEILING_24 / 2;
    for (size_t i = 0; i < CHUNK; i++) in[i] = randIn(amp);
    if (k % 11 == 0) in[k % 2 ? 0 : CHUNK - 1] = (k % 4 ? 1 : -1) * (1 << 29);
    if (lim.process(in, out)) limitedChunks++;
    for (size_t i = 0; i < CHUNK; i++) {
      TEST_ASSERT_TRUE(out[i] <= (CEILING_24 >> 8) + 1);
      TEST_ASSERT_TRUE(out[i] >= -(CEILING_24 >> 8) - 1);
    }
  }
  TEST_ASSERT_TRUE(limitedChunks > 100);   // the loud chunks really were turned down
}

void test_limiter_lets_go_after_a_peak() {
  Limiter lim;
  int32_t in[CHUNK];
  int16_t out[CHUNK];
  for (size_t i = 0; i < CHUNK; i++) in[i] = (i == 80) ? 4 * RAIL_24 : 0;   // one huge click
  lim.process(in, out);
  TEST_ASSERT_TRUE(lim.gain() < GAIN_ONE / 4);
  int32_t prev[CHUNK] = {};
  for (int k = 0; k < 8; k++) {   // 1/4 -> 1 at most 2x per chunk: back to unity well within 8 chunks
    for (size_t i = 0; i < CHUNK; i++) in[i] = randIn(RAIL_24 / 4);
    lim.process(in, out);
    for (size_t i = 0; i < CHUNK; i++) prev[i] = in[i];
  }
  TEST_ASSERT_EQUAL_INT32(GAIN_ONE, lim.gain());
  for (size_t i = 0; i < CHUNK; i++) in[i] = randIn(RAIL_24 / 4);
  TEST_ASSERT_FALSE(lim.process(in, out));
  for (size_t i = 0; i < CHUNK; i++) TEST_ASSERT_EQUAL_INT16((int16_t)(prev[i] >> 8), out[i]);
}

int main() {
  UNITY_BEGIN();
  RUN_TEST(test_dc_block_removes_offset);
  RUN_TEST(test_limiter_is_exact_below_ceiling);
  RUN_TEST(test_limiter_never_reaches_rails);
  RUN_TEST(test_limiter_lets_go_after_a_peak);
  return UNITY_END();
}
