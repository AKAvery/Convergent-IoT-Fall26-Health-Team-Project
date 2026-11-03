// ADPCM C++ vs the Python reference: every case in fixtures/adpcm/ must match byte for byte.
// Runs on the Mac, no board needed:
//
//   pio test -e native
//
// The fixtures are found relative to the firmware folder (pio test runs from there), or set
// ADPCM_FIXTURES=/path/to/fixtures/adpcm.
#include <unity.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <string>
#include <vector>

#include "ima_adpcm.h"

using namespace adpcm;

static const char* const CASES[] = {"main", "silence", "sine_1k", "square_clipped", "impulse", "esc50_dog"};

static std::string fixturesDir;

static bool readFile(const std::string& path, std::vector<uint8_t>& out) {
  FILE* f = fopen(path.c_str(), "rb");
  if (!f) return false;
  fseek(f, 0, SEEK_END);
  long n = ftell(f);
  fseek(f, 0, SEEK_SET);
  out.resize(n > 0 ? (size_t)n : 0);
  size_t got = out.empty() ? 0 : fread(out.data(), 1, out.size(), f);
  fclose(f);
  return got == out.size();
}

static std::vector<int16_t> toSamples(const std::vector<uint8_t>& b) {
  std::vector<int16_t> s(b.size() / 2);
  for (size_t i = 0; i < s.size(); i++) s[i] = (int16_t)(uint16_t)(b[2 * i] | (b[2 * i + 1] << 8));
  return s;
}

static std::vector<uint8_t> load(const char* name, const char* kind) {
  std::vector<uint8_t> b;
  std::string path = fixturesDir + "/" + name + "_" + kind + ".bin";
  if (!readFile(path, b)) {
    std::string msg = "cannot read " + path;
    TEST_FAIL_MESSAGE(msg.c_str());
  }
  return b;
}

static void findFixtures() {
  const char* env = getenv("ADPCM_FIXTURES");
  const char* candidates[] = {env, "../fixtures/adpcm", "fixtures/adpcm", "../../fixtures/adpcm"};
  for (const char* c : candidates) {
    if (!c) continue;
    std::vector<uint8_t> probe;
    if (readFile(std::string(c) + "/silence_input.bin", probe)) {
      fixturesDir = c;
      return;
    }
  }
}

void setUp() {}
void tearDown() {}

// The two worked examples in fixtures/adpcm/README.md.
static void test_readme_examples() {
  int16_t samples[SAMPLES_PER_PACKET] = {20, -20};
  State s;
  s.predictor = -1234;
  s.index = 42;
  uint8_t payload[PAYLOAD_BYTES];
  encodePayload(samples, s, payload);
  const uint8_t header[4] = {0x2E, 0xFB, 0x2A, 0x00};
  TEST_ASSERT_EQUAL_HEX8_ARRAY(header, payload, 4);

  State z;
  TEST_ASSERT_EQUAL_UINT8(7, encodeSample(20, z));
  TEST_ASSERT_EQUAL_UINT8(15, encodeSample(-20, z));
  State z2;
  encodePayload(samples, z2, payload);
  TEST_ASSERT_EQUAL_HEX8(0xF7, payload[STATE_BYTES]);
}

static void test_decoder_rejects_bad_step_index() {
  uint8_t payload[PAYLOAD_BYTES] = {0};
  payload[2] = 89;
  int16_t out[SAMPLES_PER_PACKET];
  TEST_ASSERT_FALSE(decodePayload(payload, out));
  payload[2] = 88;
  TEST_ASSERT_TRUE(decodePayload(payload, out));
}

// Encoder: <case>_input.bin from state (0, 0), seq = packet number -> <case>_packets.bin, all 169 bytes.
static void test_encoder_matches_fixtures() {
  for (const char* name : CASES) {
    std::vector<int16_t> in = toSamples(load(name, "input"));
    std::vector<uint8_t> want = load(name, "packets");
    size_t nPackets = in.size() / SAMPLES_PER_PACKET;
    char msg[96];
    snprintf(msg, sizeof msg, "%s: packet count", name);
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(want.size(), nPackets * BLE_PACKET_BYTES, msg);

    State s;
    uint8_t pkt[BLE_PACKET_BYTES];
    for (size_t p = 0; p < nPackets; p++) {
      encodeBlePacket((uint16_t)p, 0, &in[p * SAMPLES_PER_PACKET], s, pkt);
      snprintf(msg, sizeof msg, "%s: packet %u", name, (unsigned)p);
      TEST_ASSERT_EQUAL_HEX8_ARRAY_MESSAGE(&want[p * BLE_PACKET_BYTES], pkt, BLE_PACKET_BYTES, msg);
    }
  }
}

// Decoder: every packet of <case>_packets.bin decoded on its own -> <case>_decoded.bin.
static void test_decoder_matches_fixtures() {
  for (const char* name : CASES) {
    std::vector<uint8_t> pk = load(name, "packets");
    std::vector<int16_t> want = toSamples(load(name, "decoded"));
    size_t nPackets = pk.size() / BLE_PACKET_BYTES;
    char msg[96];
    snprintf(msg, sizeof msg, "%s: sample count", name);
    TEST_ASSERT_EQUAL_UINT32_MESSAGE(want.size(), nPackets * SAMPLES_PER_PACKET, msg);

    int16_t out[SAMPLES_PER_PACKET];
    for (size_t p = 0; p < nPackets; p++) {
      snprintf(msg, sizeof msg, "%s: packet %u", name, (unsigned)p);
      TEST_ASSERT_TRUE_MESSAGE(decodePayload(&pk[p * BLE_PACKET_BYTES + BLE_HEADER_BYTES], out), msg);
      TEST_ASSERT_EQUAL_INT16_ARRAY_MESSAGE(&want[p * SAMPLES_PER_PACKET], out, SAMPLES_PER_PACKET, msg);
    }
  }
}

int main() {
  findFixtures();
  UNITY_BEGIN();
  if (fixturesDir.empty()) {
    printf("fixtures/adpcm not found; run from firmware/ or set ADPCM_FIXTURES\n");
    return UNITY_END() + 1;
  }
  printf("fixtures: %s\n", fixturesDir.c_str());
  RUN_TEST(test_readme_examples);
  RUN_TEST(test_decoder_rejects_bad_step_index);
  RUN_TEST(test_encoder_matches_fixtures);
  RUN_TEST(test_decoder_matches_fixtures);
  return UNITY_END();
}
