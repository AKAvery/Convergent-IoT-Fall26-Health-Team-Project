import Foundation
import Models

/// IMA ADPCM (4-bit), the codec of the BLE `audio` packet. Reference: `ml/adpcm.py`; the firmware
/// encoder (`firmware/lib/ima_adpcm`) and this decoder must match it sample for sample, checked
/// against `fixtures/adpcm/` (see its README).
///
/// Nibble order is low nibble first. Every packet header carries the encoder state before the
/// packet's first sample, so each packet decodes on its own.
public enum IMAADPCM {
    public struct State: Equatable, Sendable {
        public var predictor: Int32
        public var index: Int32

        public init(predictor: Int16 = 0, index: UInt8 = 0) {
            self.predictor = Int32(predictor)
            self.index = Int32(min(index, 88))
        }
    }

    static let indexTable: [Int32] = [-1, -1, -1, -1, 2, 4, 6, 8,
                                      -1, -1, -1, -1, 2, 4, 6, 8]
    static let stepTable: [Int32] = [
        7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 19, 21, 23, 25, 28, 31, 34, 37, 41, 45,
        50, 55, 60, 66, 73, 80, 88, 97, 107, 118, 130, 143, 157, 173, 190, 209, 230, 253, 279, 307,
        337, 371, 408, 449, 494, 544, 598, 658, 724, 796, 876, 963, 1060, 1166, 1282, 1411, 1552, 1707, 1878, 2066,
        2272, 2499, 2749, 3024, 3327, 3660, 4026, 4428, 4871, 5358, 5894, 6484, 7132, 7845, 8630, 9493, 10442, 11487, 12635, 13899,
        15289, 16818, 18500, 20350, 22385, 24623, 27086, 29794, 32767]

    /// Decodes one 4-bit code and advances `state`.
    @inline(__always)
    static func decode(_ code: UInt8, _ state: inout State) -> Int16 {
        let step = stepTable[Int(state.index)]
        var vpdiff = step >> 3
        if code & 4 != 0 { vpdiff += step }
        if code & 2 != 0 { vpdiff += step >> 1 }
        if code & 1 != 0 { vpdiff += step >> 2 }
        if code & 8 != 0 {
            state.predictor = max(state.predictor - vpdiff, -32768)
        } else {
            state.predictor = min(state.predictor + vpdiff, 32767)
        }
        state.index = min(max(state.index + indexTable[Int(code & 0x0F)], 0), 88)
        return Int16(state.predictor)
    }

    /// Encodes one sample and advances `state`. Builds `vpdiff` by successive halving, like the
    /// reference, so encoder and decoder never drift apart.
    @inline(__always)
    static func encode(_ sample: Int16, _ state: inout State) -> UInt8 {
        var step = stepTable[Int(state.index)]
        var diff = Int32(sample) - state.predictor
        var code: UInt8 = 0
        if diff < 0 { code = 8; diff = -diff }
        var vpdiff = step >> 3
        if diff >= step { code |= 4; diff -= step; vpdiff += step }
        step >>= 1
        if diff >= step { code |= 2; diff -= step; vpdiff += step }
        step >>= 1
        if diff >= step { code |= 1; vpdiff += step }
        if code & 8 != 0 {
            state.predictor = max(state.predictor - vpdiff, -32768)
        } else {
            state.predictor = min(state.predictor + vpdiff, 32767)
        }
        state.index = min(max(state.index + indexTable[Int(code)], 0), 88)
        return code
    }

    /// Low-nibble-first packed codes -> samples, starting from `state`.
    public static func decode(codes: some Collection<UInt8>, from state: State) -> [Int16] {
        var s = state
        var out: [Int16] = []
        out.reserveCapacity(codes.count * 2)
        for byte in codes {
            out.append(decode(byte & 0x0F, &s))
            out.append(decode(byte >> 4, &s))
        }
        return out
    }

    /// The 320 samples of one BLE `audio` packet. Needs nothing from earlier packets.
    public static func decode(_ packet: AudioPacket) -> [Int16] {
        decode(codes: packet.adpcm, from: State(predictor: packet.predictor, index: packet.stepIndex))
    }

    /// Encodes 320 samples into one `audio` packet, as the box firmware does. `state` carries the
    /// encoder across packets; the header gets the state from before the first sample.
    public static func encodePacket(_ samples: ArraySlice<Int16>, seq: UInt16, state: inout State) -> AudioPacket {
        precondition(samples.count == AudioPacket.samplesPerPacket, "need \(AudioPacket.samplesPerPacket) samples")
        let header = state
        var bytes = [UInt8](repeating: 0, count: AudioPacket.adpcmByteCount)
        var clipped = false
        for (k, x) in samples.enumerated() {
            if x == .min || x == .max { clipped = true }
            let c = encode(x, &state)
            bytes[k / 2] |= (k % 2 == 0) ? c : c << 4
        }
        return AudioPacket(seq: seq, flags: clipped ? 1 : 0, predictor: Int16(header.predictor),
                           stepIndex: UInt8(header.index), adpcm: Data(bytes))
    }
}
