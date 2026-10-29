import Foundation

// Contract 2 in docs/team-plan.md: Lane 1 (Input) -> Lane 2 (Detection).

public enum BoxPosition: String, Codable, CaseIterable, Sendable {
    case front, back, left, right
}

public struct BoxLevel: Sendable {
    public let box: BoxPosition
    public let seq: UInt16
    public let receivedAt: Date
    public let peakDbfs: Float
    public let clipped: Bool

    public init(box: BoxPosition, seq: UInt16, receivedAt: Date, peakDbfs: Float, clipped: Bool) {
        self.box = box
        self.seq = seq
        self.receivedAt = receivedAt
        self.peakDbfs = peakDbfs
        self.clipped = clipped
    }
}

public struct SoundFrame: Sendable {
    public let box: BoxPosition     // which box this audio came from
    public let seq: UInt16
    public let receivedAt: Date
    public let samples: [Int16]     // 320 samples, 16 kHz mono, already ADPCM-decoded

    public init(box: BoxPosition, seq: UInt16, receivedAt: Date, samples: [Int16]) {
        self.box = box
        self.seq = seq
        self.receivedAt = receivedAt
        self.samples = samples
    }
}

public protocol BoxSource {
    var levels: AsyncStream<BoxLevel> { get }
    var frames: AsyncStream<SoundFrame> { get }
    func streamAudio(from box: BoxPosition)   // Lane 2 calls this when the loudest box changes
}
