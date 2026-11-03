import Foundation
import Models

/// The mock in contract 2: plays a 16 kHz mono 16-bit WAV as `SoundFrame`s and makes up 4
/// `BoxLevel` streams for a sound that slowly circles the wearer. Used in the Simulator (no
/// CoreBluetooth there) and in tests.
///
/// The audio goes through the same IMA ADPCM encode -> 169-byte packet -> decode path as a real
/// box, so the detector sees exactly the codec error it gets from hardware.
public final class WavFileBoxSource: BoxSource, @unchecked Sendable {
    public let levels: AsyncStream<BoxLevel>
    public let frames: AsyncStream<SoundFrame>

    private let samples: [Int16]
    private let loop: Bool
    private let realTime: Bool
    private let secondsPerTurn: Double
    private let lock = NSLock()
    private var audioBox: BoxPosition?
    private var task: Task<Void, Never>?
    private let levelOut: AsyncStream<BoxLevel>.Continuation
    private let frameOut: AsyncStream<SoundFrame>.Continuation

    /// `realTime` false runs as fast as the consumer reads (tests); true paces at 50 frames/s.
    public init(samples: [Int16], loop: Bool = true, realTime: Bool = true, secondsPerTurn: Double = 20) {
        self.samples = samples
        self.loop = loop
        self.realTime = realTime
        self.secondsPerTurn = secondsPerTurn
        (levels, levelOut) = AsyncStream.makeStream(bufferingPolicy: realTime ? .bufferingNewest(64) : .unbounded)
        (frames, frameOut) = AsyncStream.makeStream(bufferingPolicy: realTime ? .bufferingNewest(100) : .unbounded)
    }

    public convenience init(url: URL, loop: Bool = true, realTime: Bool = true) throws {
        self.init(samples: try WAV.readMono16k(url), loop: loop, realTime: realTime)
    }

    public func streamAudio(from box: BoxPosition) {
        lock.withLock { audioBox = box }
    }

    public func start() {
        lock.withLock {
            guard task == nil else { return }
            task = Task.detached(priority: .userInitiated) { [self] in await run() }
        }
    }

    public func stop() {
        lock.withLock { task?.cancel(); task = nil }
    }

    private func run() async {
        let n = AudioPacket.samplesPerPacket
        let packets = samples.count / n
        guard packets > 0 else { levelOut.finish(); frameOut.finish(); return }
        var state = IMAADPCM.State()
        var seq: UInt16 = 0
        var levelSeq: UInt16 = 0
        var windowPeak: Int32 = 0
        var k = 0
        let start = ContinuousClock.now
        while !Task.isCancelled {
            if k == packets {
                guard loop else { break }
                k = 0
            }
            let block = samples[(k * n)..<((k + 1) * n)]
            let pkt = IMAADPCM.encodePacket(block, seq: seq, state: &state)
            let decoded = IMAADPCM.decode(pkt)
            for s in block { windowPeak = max(windowPeak, abs(Int32(s))) }
            if let box = lock.withLock({ audioBox }) {
                frameOut.yield(SoundFrame(box: box, seq: seq, receivedAt: Date(), samples: decoded))
            }
            seq &+= 1
            k += 1
            if seq % 5 == 0 {   // 100 ms: one `level` per box
                emitLevels(peak: windowPeak, seq: levelSeq, t: Double(seq) * 0.02)
                levelSeq &+= 1
                windowPeak = 0
            }
            if realTime {
                try? await Task.sleep(until: start + .milliseconds(20 * Int(seq)), clock: .continuous)
            } else if seq % 50 == 0 {
                await Task.yield()
            }
        }
        levelOut.finish()
        frameOut.finish()
    }

    /// The sound circles the wearer: the box facing it hears the full level, the opposite box
    /// 12 dB less (body shadow), the side boxes in between.
    private func emitLevels(peak: Int32, seq: UInt16, t: Double) {
        let peakDb = peak > 0 ? 20 * log10(Double(peak) / 32768) : -100
        let soundDeg = (t / secondsPerTurn).truncatingRemainder(dividingBy: 1) * 360
        let now = Date()
        for box in BoxPosition.allCases {
            let off = Double(Azimuth.difference(Float(soundDeg), box.facingDeg))   // 0...180
            let db = max(peakDb - 12 * off / 180, -100)
            levelOut.yield(BoxLevel(box: box, seq: seq, receivedAt: now, peakDbfs: Float(db), clipped: false))
        }
    }
}

/// Minimal WAV I/O for 16 kHz mono 16-bit PCM, the format of the box audio.
public enum WAV {
    public enum Error: Swift.Error { case unsupported(String) }

    public static func readMono16k(_ url: URL) throws -> [Int16] {
        let d = try Data(contentsOf: url)
        guard d.count >= 12, String(decoding: d[0..<4], as: UTF8.self) == "RIFF",
              String(decoding: d[8..<12], as: UTF8.self) == "WAVE" else { throw Error.unsupported("not a WAV file") }
        var i = 12
        var fmtOK = false
        while i + 8 <= d.count {
            let id = String(decoding: d[i..<(i + 4)], as: UTF8.self)
            let size = Int(u32(d, i + 4))
            let body = (i + 8)..<min(i + 8 + size, d.count)
            if id == "fmt " {
                let format = u16(d, body.lowerBound), channels = u16(d, body.lowerBound + 2)
                let rate = u32(d, body.lowerBound + 4), bits = u16(d, body.lowerBound + 14)
                guard format == 1, channels == 1, rate == 16_000, bits == 16 else {
                    throw Error.unsupported("need 16 kHz mono 16-bit PCM, got format \(format), \(channels) ch, \(rate) Hz, \(bits) bit")
                }
                fmtOK = true
            } else if id == "data" {
                guard fmtOK else { throw Error.unsupported("data before fmt") }
                return stride(from: body.lowerBound, to: body.upperBound - 1, by: 2).map { Int16(bitPattern: u16(d, $0)) }
            }
            i = body.upperBound + (size & 1)
        }
        throw Error.unsupported("no data chunk")
    }

    public static func writeMono16k(_ samples: [Int16], to url: URL) throws {
        var d = Data()
        func put32(_ v: UInt32) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        func put16(_ v: UInt16) { withUnsafeBytes(of: v.littleEndian) { d.append(contentsOf: $0) } }
        let bytes = UInt32(samples.count * 2)
        d.append(contentsOf: Array("RIFF".utf8)); put32(36 + bytes); d.append(contentsOf: Array("WAVE".utf8))
        d.append(contentsOf: Array("fmt ".utf8)); put32(16); put16(1); put16(1); put32(16_000); put32(32_000)
        put16(2); put16(16)
        d.append(contentsOf: Array("data".utf8)); put32(bytes)
        for s in samples { put16(UInt16(bitPattern: s)) }
        try d.write(to: url)
    }

    private static func u16(_ d: Data, _ i: Int) -> UInt16 {
        UInt16(d[d.startIndex + i]) | UInt16(d[d.startIndex + i + 1]) << 8
    }

    private static func u32(_ d: Data, _ i: Int) -> UInt32 {
        UInt32(u16(d, i)) | UInt32(u16(d, i + 2)) << 16
    }
}
