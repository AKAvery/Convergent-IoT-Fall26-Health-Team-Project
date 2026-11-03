// ima_adpcm.h — IMA ADPCM (4-bit) encoder/decoder for the box -> iPhone `audio` packets.
//
// C++ port of ml/adpcm.py (the reference). Must match it byte for byte; checked against
// fixtures/adpcm/ by `pio test -e native` (test/test_adpcm). Format details are in
// fixtures/adpcm/README.md; the short version:
//
//   - Standard IMA / DVI arithmetic: 89-entry step table, predictor clamped to int16,
//     step index clamped to 0..88. Code = sign (bit 3) + magnitude (bits 2..0).
//   - 320 samples (20 ms at 16 kHz) per packet. Payload = 4-byte state header
//     (predictor int16 LE, step index u8, pad 0) + 160 bytes of codes, LOW NIBBLE FIRST.
//   - The header is the encoder state BEFORE the packet's first sample, so every packet
//     decodes on its own. The encoder itself runs continuously across packets.
//   - BLE `audio` packet (169 B) = seq u16 LE, reserved u16 = 0, flags u8, then the payload.
//
// No Arduino dependencies, so the same code builds for the ESP32 and for the native tests.
#pragma once

#include <stddef.h>
#include <stdint.h>

namespace adpcm {

constexpr size_t SAMPLES_PER_PACKET = 320;
constexpr size_t CODE_BYTES = SAMPLES_PER_PACKET / 2;              // 160
constexpr size_t STATE_BYTES = 4;
constexpr size_t PAYLOAD_BYTES = STATE_BYTES + CODE_BYTES;         // 164
constexpr size_t BLE_HEADER_BYTES = 5;                             // seq u16, reserved u16, flags u8
constexpr size_t BLE_PACKET_BYTES = BLE_HEADER_BYTES + PAYLOAD_BYTES;  // 169

constexpr uint8_t FLAG_CLIPPED = 1 << 0;

struct State {
  int16_t predictor = 0;
  uint8_t index = 0;       // 0..88
};

// One sample -> one 4-bit code; updates `s`.
uint8_t encodeSample(int16_t x, State& s);

// One 4-bit code -> one sample; updates `s`.
int16_t decodeSample(uint8_t code, State& s);

// 320 samples -> 164-byte payload (state header + codes). `s` carries over to the next packet.
void encodePayload(const int16_t samples[SAMPLES_PER_PACKET], State& s, uint8_t out[PAYLOAD_BYTES]);

// 164-byte payload -> 320 samples, using only the packet's own header.
// Returns false (and leaves `out` untouched) if the header's step index is out of range.
bool decodePayload(const uint8_t in[PAYLOAD_BYTES], int16_t out[SAMPLES_PER_PACKET]);

// The full 169-byte BLE `audio` notification for 320 samples. `flags` is ORed with
// FLAG_CLIPPED when any sample is -32768 or 32767 (the rule the fixtures use).
void encodeBlePacket(uint16_t seq, uint8_t flags, const int16_t samples[SAMPLES_PER_PACKET], State& s,
                     uint8_t out[BLE_PACKET_BYTES]);

}  // namespace adpcm
