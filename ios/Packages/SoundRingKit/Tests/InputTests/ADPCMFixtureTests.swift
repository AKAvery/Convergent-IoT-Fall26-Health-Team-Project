import Foundation
import Testing
@testable import Input
import Models

/// The repo's fixtures/ directory (shared with ml/ and firmware/).
let fixturesDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("fixtures")

private struct Manifest: Decodable {
    struct Case: Decodable {
        let name: String
        let n_samples: Int
        let n_packets: Int
        let files: [String: String]
    }
    let cases: [Case]
}

private func int16s(_ url: URL) throws -> [Int16] {
    let d = try Data(contentsOf: url)
    return stride(from: 0, to: d.count, by: 2).map { Int16(bitPattern: UInt16(d[$0]) | UInt16(d[$0 + 1]) << 8) }
}

private let adpcmCases: [String] = {
    let url = fixturesDir.appendingPathComponent("adpcm/manifest.json")
    guard let d = try? Data(contentsOf: url), let m = try? JSONDecoder().decode(Manifest.self, from: d) else { return [] }
    return m.cases.map(\.name)
}()

@Suite struct ADPCMFixtureTests {
    private func load(_ name: String) throws -> (input: [Int16], packets: [Data], decoded: [Int16]) {
        let dir = fixturesDir.appendingPathComponent("adpcm")
        let raw = try Data(contentsOf: dir.appendingPathComponent("\(name)_packets.bin"))
        #expect(raw.count % AudioPacket.byteCount == 0)
        let packets = stride(from: 0, to: raw.count, by: AudioPacket.byteCount).map {
            raw.subdata(in: $0..<($0 + AudioPacket.byteCount))
        }
        return (try int16s(dir.appendingPathComponent("\(name)_input.bin")), packets,
                try int16s(dir.appendingPathComponent("\(name)_decoded.bin")))
    }

    @Test func manifestHasCases() {
        #expect(adpcmCases.count >= 6, "fixtures/adpcm/manifest.json not found or empty at \(fixturesDir.path)")
    }

    /// The phone decodes each packet on its own and must get the reference samples exactly.
    @Test(arguments: adpcmCases)
    func decodeMatchesReference(name: String) throws {
        let f = try load(name)
        var out: [Int16] = []
        for p in f.packets { out += IMAADPCM.decode(try AudioPacket(p)) }
        #expect(out.count == f.decoded.count)
        let firstDiff = zip(out, f.decoded).enumerated().first { $0.element.0 != $0.element.1 }?.offset
        #expect(firstDiff == nil, "first mismatch at sample \(firstDiff ?? -1)")
    }

    /// The encoder (used by WavFileBoxSource to mimic a box) produces the reference packets byte
    /// for byte, header included.
    @Test(arguments: adpcmCases)
    func encodeMatchesReference(name: String) throws {
        let f = try load(name)
        var state = IMAADPCM.State()
        let n = AudioPacket.samplesPerPacket
        for (k, expected) in f.packets.enumerated() {
            let pkt = IMAADPCM.encodePacket(f.input[(k * n)..<((k + 1) * n)], seq: UInt16(k), state: &state)
            #expect(pkt.encoded() == expected, "packet \(k) differs")
            if pkt.encoded() != expected { break }
        }
    }
}

@Suite struct WavFileBoxSourceTests {
    @Test func wavRoundTrip() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("soundring-test-\(UUID()).wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let samples: [Int16] = (0..<1000).map { Int16(truncatingIfNeeded: $0 * 37) }
        try WAV.writeMono16k(samples, to: url)
        #expect(try WAV.readMono16k(url) == samples)
    }

    /// Frames come out ADPCM-decoded, in order, only after streamAudio(from:), with 4 boxes of levels.
    @Test func emitsDecodedFramesAndLevels() async throws {
        let input = try int16s(fixturesDir.appendingPathComponent("adpcm/main_input.bin"))
        let expected = try int16s(fixturesDir.appendingPathComponent("adpcm/main_decoded.bin"))
        let src = WavFileBoxSource(samples: input, loop: false, realTime: false)
        src.streamAudio(from: .back)
        src.start()
        var frames: [SoundFrame] = []
        for await f in src.frames { frames.append(f) }
        var levels: [BoxLevel] = []
        for await l in src.levels { levels.append(l) }
        #expect(frames.count == input.count / AudioPacket.samplesPerPacket)
        #expect(frames.allSatisfy { $0.box == .back })
        #expect(frames.map(\.seq) == (0..<UInt16(frames.count)).map { $0 })
        #expect(frames.flatMap(\.samples) == Array(expected.prefix(frames.count * AudioPacket.samplesPerPacket)))
        #expect(Set(levels.map(\.box)) == Set(BoxPosition.allCases))
    }
}
