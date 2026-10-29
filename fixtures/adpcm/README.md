# IMA ADPCM test vectors

Reference: `ml/adpcm.py`. Regenerate with `python3 ml/make_adpcm_fixtures.py` (deterministic, needs
`ml/data/ESC-50` for the real-audio cases); check with `python3 ml/test_adpcm.py`.

## Codec

- Standard IMA / DVI ADPCM, 4 bits per sample, 16 kHz mono int16. Same arithmetic as the IMA
  reference code (CPython's `audioop.lin2adpcm` gives identical codes; the test checks this).
  89-entry step table, index table `-1 -1 -1 -1 2 4 6 8` (repeated for the sign bit), predictor
  clamped to -32768..32767, step index clamped to 0..88. Code = sign bit 3 + magnitude bits 2..0.
- Decoder per code: `vpdiff = step>>3; if c&4 vpdiff += step; if c&2 vpdiff += step>>1;
  if c&1 vpdiff += step>>2; pred ±= vpdiff (minus if c&8); clamp; index += INDEX[c]; clamp`.
  The encoder must build `vpdiff` the same way (successive `step >>= 1`), not by multiplication.
- **Nibble order: low nibble first.** `byte[k] = code[2k] | (code[2k+1] << 4)`.
  (`audioop` packs high nibble first; don't copy that.)
- All 320 samples of a packet are coded as nibbles. The header predictor is the encoder state, not
  an extra raw sample (unlike the Microsoft WAV IMA block format).
- The encoder runs continuously and starts at predictor 0, step index 0. Each packet header is a
  snapshot of the state *before* that packet's first sample, so every packet decodes on its own
  and gives exactly what a continuous decode gives.

## Packet (169 bytes, the BLE `audio` characteristic in docs/team-plan.md)

| offset | size | field | |
|---|---|---|---|
| 0 | 2 | seq | uint16 LE; 0 for the first packet of each case here |
| 2 | 2 | reserved | 0 |
| 4 | 1 | flags | bit0 = clipped. In these files: set if any input sample of the packet is -32768 or 32767 |
| 5 | 2 | predictor | int16 LE |
| 7 | 1 | step index | uint8, 0..88 |
| 8 | 1 | pad | 0 |
| 9 | 160 | codes | 320 x 4 bits, low nibble first |

Example: state (-1234, 42) is header bytes `2E FB 2A 00`. Samples `[20, -20]` from state (0, 0)
encode to codes `7, 15`, i.e. the byte `F7`.

## Files

All `.bin` files are raw little-endian: `*_input.bin` and `*_decoded.bin` are int16 samples,
`*_packets.bin` is the packets back to back (n_packets x 169 bytes). `manifest.json` lists every
case with sample/packet counts, sha256 of each file, max |error| and SNR.

| case | packets | what |
|---|---|---|
| `main` | 150 | 3 s: log sweep 100 Hz-7 kHz at -6 dBFS, an ESC-50 clap (`1-104089-A-22.wav`) at -3 dBFS, 1 s silence. Also as `input.wav`, `packets.bin`, `decoded.wav` (16-bit WAV) |
| `silence` | 3 | digital zeros (decodes to exact zeros) |
| `sine_1k` | 10 | 1 kHz sine at -6 dBFS |
| `square_clipped` | 10 | full-scale 250 Hz square: slope overload, predictor clamp, clipped flag set |
| `impulse` | 3 | isolated full-scale impulses in silence: step-index ramp from 0, clamp |
| `esc50_dog` | 50 | loudest 1 s of ESC-50 `1-100032-A-0.wav`, -3 dBFS |

The `square_clipped` and `impulse` cases have large errors on purpose: 4-bit ADPCM cannot follow a
full-scale step from a small step size. They exist to pin down clamping, not to show quality.

## What each implementation must pass

- **C++ encoder (firmware):** from `<case>_input.bin`, starting at state (0, 0), produce
  `<case>_packets.bin` byte for byte (at minimum bytes 5..168 of every packet; the seq/flags rules
  above if the test also builds the header).
- **Swift decoder (iPhone):** decode each 169-byte packet of `<case>_packets.bin` on its own and
  reproduce `<case>_decoded.bin` sample for sample.

ESC-50 excerpts: Piczak, ESC: Dataset for Environmental Sound Classification, CC BY-NC 3.0.
