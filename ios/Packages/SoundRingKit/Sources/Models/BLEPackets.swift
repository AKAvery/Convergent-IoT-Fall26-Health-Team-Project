import Foundation

// Contract 1 in docs/team-plan.md (draft v0): the bytes each box sends over BLE.
// All multi-byte fields are little-endian. Parsing is pure: Data in, struct out.
// ADPCM decoding is not here; it lives in Input (B1).

public enum BLEPacketError: Error, Equatable {
    case wrongLength(expected: Int, got: Int)
}

extension BoxPosition {
    /// The name the box advertises, e.g. `SoundBox-FRONT`.
    public var advertisedName: String { "SoundBox-" + rawValue.uppercased() }

    public init?(advertisedName: String) {
        let prefix = "SoundBox-"
        guard advertisedName.hasPrefix(prefix),
              let box = BoxPosition(rawValue: advertisedName.dropFirst(prefix.count).lowercased())
        else { return nil }
        self = box
    }
}

/// `level` characteristic: 5 bytes, 10 Hz, always on.
public struct LevelPacket: Equatable, Sendable {
    public static let byteCount = 5

    public var seq: UInt16
    /// dBFS × 10, peak of the last 100 ms, exactly as sent.
    public var peakDbfsX10: Int16
    /// bit0 = clipped, bit1 = low battery. Unknown bits are kept.
    public var flags: UInt8

    public var peakDbfs: Float { Float(peakDbfsX10) / 10 }
    public var clipped: Bool { flags & 0b01 != 0 }
    public var lowBattery: Bool { flags & 0b10 != 0 }

    public init(seq: UInt16, peakDbfsX10: Int16, flags: UInt8) {
        self.seq = seq
        self.peakDbfsX10 = peakDbfsX10
        self.flags = flags
    }

    public init(seq: UInt16, peakDbfsX10: Int16, clipped: Bool, lowBattery: Bool) {
        self.init(seq: seq, peakDbfsX10: peakDbfsX10,
                  flags: (clipped ? 0b01 : 0) | (lowBattery ? 0b10 : 0))
    }

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        guard b.count == Self.byteCount else {
            throw BLEPacketError.wrongLength(expected: Self.byteCount, got: b.count)
        }
        self.init(seq: readU16(b, 0), peakDbfsX10: Int16(bitPattern: readU16(b, 2)), flags: b[4])
    }

    public func encoded() -> Data {
        var b: [UInt8] = []
        b.reserveCapacity(Self.byteCount)
        appendU16(&b, seq)
        appendU16(&b, UInt16(bitPattern: peakDbfsX10))
        b.append(flags)
        return Data(b)
    }

    public func boxLevel(box: BoxPosition, receivedAt: Date) -> BoxLevel {
        BoxLevel(box: box, seq: seq, receivedAt: receivedAt, peakDbfs: peakDbfs, clipped: clipped)
    }
}

/// `audio` characteristic: 169 bytes, 50 Hz, only while `control` = 1.
public struct AudioPacket: Equatable, Sendable {
    public static let byteCount = 169
    public static let adpcmByteCount = 160
    public static let samplesPerPacket = 320
    public static let sampleRate = 16_000

    public var seq: UInt16
    /// bit0 = clipped. Unknown bits are kept.
    public var flags: UInt8
    /// IMA ADPCM encoder state before this packet's first sample.
    public var predictor: Int16
    public var stepIndex: UInt8
    /// 160 bytes = 320 samples, 4-bit IMA ADPCM, low nibble first.
    public var adpcm: Data

    public var clipped: Bool { flags & 0b01 != 0 }

    public init(seq: UInt16, flags: UInt8, predictor: Int16, stepIndex: UInt8, adpcm: Data) {
        self.seq = seq
        self.flags = flags
        self.predictor = predictor
        self.stepIndex = stepIndex
        self.adpcm = adpcm
    }

    public init(_ data: Data) throws {
        let b = [UInt8](data)
        guard b.count == Self.byteCount else {
            throw BLEPacketError.wrongLength(expected: Self.byteCount, got: b.count)
        }
        // bytes 2–3 reserved, byte 8 pad: ignored on read.
        self.init(seq: readU16(b, 0),
                  flags: b[4],
                  predictor: Int16(bitPattern: readU16(b, 5)),
                  stepIndex: b[7],
                  adpcm: Data(b[9..<Self.byteCount]))
    }

    /// Writes reserved and pad as 0. `adpcm` must be exactly 160 bytes.
    public func encoded() -> Data {
        precondition(adpcm.count == Self.adpcmByteCount, "adpcm must be \(Self.adpcmByteCount) bytes")
        var b: [UInt8] = []
        b.reserveCapacity(Self.byteCount)
        appendU16(&b, seq)
        appendU16(&b, 0)            // reserved
        b.append(flags)
        appendU16(&b, UInt16(bitPattern: predictor))
        b.append(stepIndex)
        b.append(0)                 // pad
        b.append(contentsOf: adpcm)
        return Data(b)
    }
}

/// `control` characteristic: 1 byte written by the phone.
public enum ControlCommand: UInt8, Sendable {
    case stopAudio = 0
    case startAudio = 1

    public var data: Data { Data([rawValue]) }
}

public enum BLESequence {
    /// Packets lost between two consecutive packets, handling the uint16 wrap
    /// (65535 -> 0 is 0 missed). A repeated seq counts as 0 missed.
    public static func missed(previous: UInt16, current: UInt16) -> Int {
        let step = current &- previous
        return step == 0 ? 0 : Int(step) - 1
    }
}

private func readU16(_ b: [UInt8], _ i: Int) -> UInt16 {
    UInt16(b[i]) | UInt16(b[i + 1]) << 8
}

private func appendU16(_ b: inout [UInt8], _ v: UInt16) {
    b.append(UInt8(truncatingIfNeeded: v))
    b.append(UInt8(truncatingIfNeeded: v >> 8))
}
