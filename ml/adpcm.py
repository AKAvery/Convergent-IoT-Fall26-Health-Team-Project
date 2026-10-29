"""
IMA ADPCM (4-bit) for the box -> iPhone `audio` packets. Reference implementation: the C++ encoder
(firmware) and the Swift decoder (iPhone) must match this module byte for byte / sample for sample,
checked against fixtures/adpcm/ (see fixtures/adpcm/README.md).

Codec: standard IMA / DVI ADPCM, the same arithmetic as the IMA reference code (and CPython's
audioop.lin2adpcm): 89-entry step table, 16-entry index table, predictor clamped to int16,
step index clamped to 0..88. Each 4-bit code is sign (bit 3) + magnitude (bits 2..0).

Packet: 320 int16 samples (20 ms at 16 kHz mono) -> 164 bytes of ADPCM payload:

    offset  size  field
    0       2     predictor   int16 LE   encoder state BEFORE the packet's first sample
    2       1     step_index  uint8      0..88, same moment
    3       1     pad         uint8      always 0
    4       160   codes       320 x 4-bit codes, 2 per byte

NIBBLE ORDER: LOW NIBBLE FIRST. Byte k holds sample 2k in bits 0..3 and sample 2k+1 in bits 4..7:
    byte[k] = code[2k] | (code[2k+1] << 4)
(Note: audioop.lin2adpcm packs the other way round, high nibble first.)

All 320 samples are coded as nibbles; the header predictor is NOT an extra raw sample (unlike
Microsoft's WAV IMA ADPCM block format). The encoder runs continuously across packets; the header just
snapshots its state, so any packet decodes on its own and gives exactly what a continuous decode gives.

In the BLE `audio` characteristic (docs/team-plan.md, 169 bytes) the payload sits at offset 5, after
seq (uint16 LE), reserved (uint16, 0) and flags (uint8, bit0 = clipped). `ble_packet()` builds it.
"""
import struct
import numpy as np

SAMPLES_PER_PACKET = 320
CODE_BYTES = SAMPLES_PER_PACKET // 2            # 160
STATE_BYTES = 4
PAYLOAD_BYTES = STATE_BYTES + CODE_BYTES        # 164
BLE_HEADER_BYTES = 5                            # seq u16, reserved u16, flags u8
BLE_PACKET_BYTES = BLE_HEADER_BYTES + PAYLOAD_BYTES   # 169

INDEX_TABLE = (-1, -1, -1, -1, 2, 4, 6, 8,
               -1, -1, -1, -1, 2, 4, 6, 8)
STEP_TABLE = (
    7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
    50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
    337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
    2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
    15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767)


def encode_codes(samples, state=(0, 0)):
    """int16 samples -> (list of 4-bit codes, state after the last sample). state = (predictor, index)."""
    pred, index = int(state[0]), int(state[1])
    step_t, idx_t = STEP_TABLE, INDEX_TABLE
    codes = []
    append = codes.append
    for x in np.asarray(samples, dtype=np.int16).tolist():
        step = step_t[index]
        diff = x - pred
        if diff < 0:
            code = 8; diff = -diff
        else:
            code = 0
        vpdiff = step >> 3
        if diff >= step:
            code |= 4; diff -= step; vpdiff += step
        step >>= 1
        if diff >= step:
            code |= 2; diff -= step; vpdiff += step
        step >>= 1
        if diff >= step:
            code |= 1; vpdiff += step
        if code & 8:
            pred -= vpdiff
            if pred < -32768: pred = -32768
        else:
            pred += vpdiff
            if pred > 32767: pred = 32767
        index += idx_t[code]
        if index < 0: index = 0
        elif index > 88: index = 88
        append(code)
    return codes, (pred, index)


def decode_codes(codes, state=(0, 0)):
    """4-bit codes -> (int16 array, state after the last sample)."""
    pred, index = int(state[0]), int(state[1])
    step_t, idx_t = STEP_TABLE, INDEX_TABLE
    out = []
    append = out.append
    for code in codes:
        step = step_t[index]
        vpdiff = step >> 3
        if code & 4: vpdiff += step
        if code & 2: vpdiff += step >> 1
        if code & 1: vpdiff += step >> 2
        if code & 8:
            pred -= vpdiff
            if pred < -32768: pred = -32768
        else:
            pred += vpdiff
            if pred > 32767: pred = 32767
        index += idx_t[code]
        if index < 0: index = 0
        elif index > 88: index = 88
        append(pred)
    return np.array(out, dtype=np.int16), (pred, index)


def pack_nibbles(codes):
    """Low nibble first: byte k = codes[2k] | codes[2k+1] << 4."""
    c = np.asarray(codes, dtype=np.uint8)
    if len(c) % 2:
        c = np.append(c, np.uint8(0))
    return (c[0::2] | (c[1::2] << 4)).astype(np.uint8).tobytes()


def unpack_nibbles(data):
    b = np.frombuffer(bytes(data), dtype=np.uint8)
    out = np.empty(2 * len(b), dtype=np.uint8)
    out[0::2] = b & 0x0F
    out[1::2] = b >> 4
    return out.tolist()


def pack_state(state):
    return struct.pack("<hBB", int(state[0]), int(state[1]), 0)


def unpack_state(data):
    pred, index, _pad = struct.unpack("<hBB", bytes(data[:STATE_BYTES]))
    if index > 88:
        raise ValueError(f"step index {index} out of range 0..88")
    return pred, index


# --------------------------------------------------------------- packets --
def encode_packet(samples, state=(0, 0)):
    """320 int16 samples -> (164-byte payload, state after the packet)."""
    if len(samples) != SAMPLES_PER_PACKET:
        raise ValueError(f"need {SAMPLES_PER_PACKET} samples, got {len(samples)}")
    codes, new_state = encode_codes(samples, state)
    return pack_state(state) + pack_nibbles(codes), new_state


def decode_packet(payload):
    """164-byte payload (state header + codes) -> 320 int16 samples. Needs nothing from earlier packets."""
    if len(payload) != PAYLOAD_BYTES:
        raise ValueError(f"need {PAYLOAD_BYTES} bytes, got {len(payload)}")
    samples, _ = decode_codes(unpack_nibbles(payload[STATE_BYTES:]), unpack_state(payload))
    return samples


def encode(samples, state=(0, 0)):
    """int16 samples -> concatenated 164-byte payloads. The last packet is zero-padded to 320 samples."""
    x = np.asarray(samples, dtype=np.int16)
    rem = (-len(x)) % SAMPLES_PER_PACKET
    if rem:
        x = np.concatenate([x, np.zeros(rem, dtype=np.int16)])
    out = bytearray()
    for i in range(0, len(x), SAMPLES_PER_PACKET):
        payload, state = encode_packet(x[i:i + SAMPLES_PER_PACKET], state)
        out += payload
    return bytes(out)


def decode(data, state=None):
    """Two forms:
    decode(payloads)        concatenated 164-byte payloads (each carries its own state) -> int16 samples
    decode(codes, state)    raw packed code bytes (no headers), decoded from `state` -> int16 samples"""
    if state is not None:
        return decode_codes(unpack_nibbles(data), state)[0]
    if len(data) % PAYLOAD_BYTES:
        raise ValueError(f"length {len(data)} is not a multiple of {PAYLOAD_BYTES}")
    parts = [decode_packet(data[i:i + PAYLOAD_BYTES]) for i in range(0, len(data), PAYLOAD_BYTES)]
    return np.concatenate(parts) if parts else np.zeros(0, dtype=np.int16)


def ble_packet(seq, payload, clipped=False):
    """The 169-byte BLE `audio` notification: seq u16 LE, reserved u16 = 0, flags u8, then the payload."""
    return struct.pack("<HHB", seq & 0xFFFF, 0, 1 if clipped else 0) + bytes(payload)


def parse_ble_packet(pkt):
    if len(pkt) != BLE_PACKET_BYTES:
        raise ValueError(f"need {BLE_PACKET_BYTES} bytes, got {len(pkt)}")
    seq, _reserved, flags = struct.unpack("<HHB", bytes(pkt[:BLE_HEADER_BYTES]))
    return {"seq": seq, "clipped": bool(flags & 1), "payload": bytes(pkt[BLE_HEADER_BYTES:])}


# ----------------------------------------------------------- float helpers --
def float_to_int16(y):
    """float audio in [-1, 1) -> int16, rounded and clipped (what a 16-bit mic front end delivers)."""
    return np.clip(np.round(np.asarray(y, dtype=np.float64) * 32768.0), -32768, 32767).astype(np.int16)


def roundtrip_float(y):
    """float32 audio -> int16 -> ADPCM encode -> decode -> float32 (same length). The eval harness uses this."""
    x = float_to_int16(y)
    codes, _ = encode_codes(x)            # continuous encoder == packetised encoder (headers are snapshots)
    return (decode_codes(codes)[0].astype(np.float32) / 32768.0)
