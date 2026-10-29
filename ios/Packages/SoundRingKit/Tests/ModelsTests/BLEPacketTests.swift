import Foundation
import Testing
@testable import Models

@Suite struct LevelPacketTests {
    @Test func parsesHandBuiltBytes() throws {
        // seq 0x1234, peak -123.4 dBFS = -1234 = 0xFB2E, flags clipped + low battery
        let bytes = Data([0x34, 0x12, 0x2E, 0xFB, 0x03])
        let p = try LevelPacket(bytes)
        #expect(p.seq == 0x1234)
        #expect(p.peakDbfsX10 == -1234)
        #expect(abs(p.peakDbfs - -123.4) < 0.0001)
        #expect(p.clipped)
        #expect(p.lowBattery)
        #expect(p.encoded() == bytes)
    }

    @Test func flagsAreIndependent() throws {
        #expect(try LevelPacket(Data([0, 0, 0, 0, 0x01])).clipped)
        #expect(try !LevelPacket(Data([0, 0, 0, 0, 0x01])).lowBattery)
        #expect(try LevelPacket(Data([0, 0, 0, 0, 0x02])).lowBattery)
        #expect(try !LevelPacket(Data([0, 0, 0, 0, 0x02])).clipped)
    }

    @Test(arguments: [UInt16(0), 1, 0x7FFF, 0x8000, 0xFFFE, 0xFFFF])
    func seqRoundTrips(seq: UInt16) throws {
        let p = LevelPacket(seq: seq, peakDbfsX10: -600, clipped: false, lowBattery: false)
        let bytes = p.encoded()
        #expect(bytes.count == LevelPacket.byteCount)
        #expect(try LevelPacket(bytes) == p)
    }

    @Test func peakExtremes() throws {
        for v in [Int16.min, -1, 0, 1, Int16.max] {
            let p = LevelPacket(seq: 7, peakDbfsX10: v, flags: 0)
            #expect(try LevelPacket(p.encoded()).peakDbfsX10 == v)
        }
    }

    @Test func toBoxLevel() throws {
        let t = Date(timeIntervalSince1970: 42)
        let level = try LevelPacket(Data([0x05, 0x00, 0xA8, 0xFD, 0x01])).boxLevel(box: .left, receivedAt: t)
        #expect(level.box == .left)
        #expect(level.seq == 5)
        #expect(abs(level.peakDbfs - -60.0) < 0.0001)   // 0xFDA8 = -600
        #expect(level.clipped)
        #expect(level.receivedAt == t)
    }

    @Test func rejectsWrongLength() {
        #expect(throws: BLEPacketError.wrongLength(expected: 5, got: 4)) {
            try LevelPacket(Data([0, 0, 0, 0]))
        }
        #expect(throws: BLEPacketError.wrongLength(expected: 5, got: 7)) {
            try LevelPacket(Data(count: 7))
        }
    }

    @Test func parsesSlicedData() throws {
        // Data slices keep their parent's indices; parsing must not assume startIndex == 0.
        let parent = Data([0xAA, 0xBB, 0x01, 0x00, 0x00, 0x00, 0x00])
        let p = try LevelPacket(parent[2...])
        #expect(p.seq == 1)
    }
}

@Suite struct AudioPacketTests {
    private func handBuilt() -> (Data, [UInt8]) {
        let adpcm = (0..<160).map { UInt8(truncatingIfNeeded: $0 &* 7 &+ 3) }
        var b: [UInt8] = [
            0xFF, 0xFF,       // seq 65535
            0x00, 0x00,       // reserved
            0x01,             // flags: clipped
            0x18, 0xFC,       // predictor -1000 = 0xFC18
            0x2A,             // step index 42
            0x00,             // pad
        ]
        b += adpcm
        return (Data(b), adpcm)
    }

    @Test func parsesHandBuiltBytes() throws {
        let (bytes, adpcm) = handBuilt()
        #expect(bytes.count == 169)
        let p = try AudioPacket(bytes)
        #expect(p.seq == 0xFFFF)
        #expect(p.clipped)
        #expect(p.predictor == -1000)
        #expect(p.stepIndex == 42)
        #expect(p.adpcm == Data(adpcm))
        #expect(p.encoded() == bytes)
    }

    @Test func ignoresReservedAndPadOnRead() throws {
        var (bytes, _) = handBuilt()
        bytes[2] = 0x99; bytes[3] = 0x99; bytes[8] = 0x77
        let p = try AudioPacket(bytes)
        #expect(p.stepIndex == 42)
        let re = p.encoded()
        #expect(re[2] == 0 && re[3] == 0 && re[8] == 0)
    }

    @Test(arguments: [UInt16(0), 1, 0xFFFE, 0xFFFF])
    func seqRoundTrips(seq: UInt16) throws {
        let p = AudioPacket(seq: seq, flags: 0, predictor: Int16.min, stepIndex: 88,
                            adpcm: Data(repeating: 0x5A, count: 160))
        #expect(try AudioPacket(p.encoded()) == p)
    }

    @Test func constantsMatchContract() {
        #expect(AudioPacket.byteCount == 9 + AudioPacket.adpcmByteCount)
        #expect(AudioPacket.adpcmByteCount * 2 == AudioPacket.samplesPerPacket)   // 4 bits/sample
        #expect(AudioPacket.byteCount <= 185 - 3)   // fits a 185-byte ATT MTU (3-byte header)
    }

    @Test func rejectsWrongLength() {
        #expect(throws: BLEPacketError.wrongLength(expected: 169, got: 168)) {
            try AudioPacket(Data(count: 168))
        }
    }
}

@Suite struct SequenceAndControlTests {
    @Test func missedCountsAcrossWrap() {
        #expect(BLESequence.missed(previous: 10, current: 11) == 0)
        #expect(BLESequence.missed(previous: 10, current: 14) == 3)
        #expect(BLESequence.missed(previous: 0xFFFF, current: 0) == 0)
        #expect(BLESequence.missed(previous: 0xFFFE, current: 1) == 2)
        #expect(BLESequence.missed(previous: 5, current: 5) == 0)
    }

    @Test func controlBytes() {
        #expect(ControlCommand.startAudio.data == Data([1]))
        #expect(ControlCommand.stopAudio.data == Data([0]))
    }

    @Test func advertisedNames() {
        #expect(BoxPosition.front.advertisedName == "SoundBox-FRONT")
        #expect(BoxPosition.right.advertisedName == "SoundBox-RIGHT")
        for box in BoxPosition.allCases {
            #expect(BoxPosition(advertisedName: box.advertisedName) == box)
        }
        #expect(BoxPosition(advertisedName: "SoundBox-UP") == nil)
        #expect(BoxPosition(advertisedName: "Other-FRONT") == nil)
    }
}
