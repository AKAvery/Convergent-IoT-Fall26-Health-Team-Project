import Foundation
import Models
import OSLog

/// What the app shows while listening (and what helps when debugging a box).
public struct DetectionStatus: Sendable {
    public var streamingBox: BoxPosition?
    /// dB above quiet level per box (nil = not reporting).
    public var loudness: [BoxPosition: Float] = [:]
    public var azimuthDeg: Float?
    public var levelDb: Double = -180
    public var gated = true
    public var top3: [(label: String, prob: Float)] = []
    /// The detector hears speech right now (its `speech` hit fired on the latest update).
    public var speechActive = false
    /// How many times speech has stopped (a counter, so a listener can't miss one between updates).
    public var speechEnds = 0
    public var framesReceived = 0
    public var framesMissed = 0

    public init() {}
}

/// Lane 2 end to end: `BoxSource` (levels + decoded audio) -> direction, loudest-box switching,
/// YAMNet + head through `Detector`, event tracking -> `SoundEvent` snapshots.
public actor DetectionEngine: SoundEventSource {
    public nonisolated let activeEvents: AsyncStream<[SoundEvent]>
    public nonisolated let statusUpdates: AsyncStream<DetectionStatus>
    /// Every audio frame the detector got, in order (for listeners that want the same audio, e.g.
    /// name alerts). Keeps the newest 5 s if nobody reads it.
    public nonisolated let audioFrames: AsyncStream<SoundFrame>

    private let audioOut: AsyncStream<SoundFrame>.Continuation
    private let eventsOut: AsyncStream<[SoundEvent]>.Continuation
    private let statusOut: AsyncStream<DetectionStatus>.Continuation
    private let source: any BoxSource & Sendable
    private let detector: Detector
    private var direction: DirectionTracker
    private var tracker: EventTracker
    private var pending: [Float] = []
    private var lastFrame: (box: BoxPosition, seq: UInt16)?
    private var status = DetectionStatus()
    private let t0 = Date()

    /// Missing audio packets up to this many are filled with silence to keep timing; longer gaps
    /// (a box switch, a drop-out) just continue.
    private let maxFill = 10

    public init(source: any BoxSource & Sendable, classifier: any SoundClassifier,
                params: DetectorParams = DetectorParams(), rules: LabelRules,
                direction: DirectionConfig = DirectionConfig()) {
        self.source = source
        self.detector = Detector(params: params, classifier: classifier, preset: "all")
        self.direction = DirectionTracker(config: direction)
        self.tracker = EventTracker(rules: rules)
        (activeEvents, eventsOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (statusUpdates, statusOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (audioFrames, audioOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(250))
    }

    /// Runs until the task is cancelled or the source finishes.
    public func run() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { for await level in self.source.levels { await self.handle(level) } }
            group.addTask { for await frame in self.source.frames { await self.handle(frame) } }
        }
        eventsOut.finish()
        statusOut.finish()
        audioOut.finish()
    }

    private func now() -> Double { Date().timeIntervalSince(t0) }

    private static let log = Logger(subsystem: "edu.utexas.convergent.soundring", category: "direction")
    private var lastLevelLog = 0.0

    /// One line per box: raw peak now, quiet level, loudness (dB above quiet, peak-held).
    private func levelsLine(at t: Double) -> String {
        BoxPosition.allCases.compactMap { b -> String? in
            guard let q = direction.quietLevel(b) else { return nil }
            let l = direction.loudness(b, at: t).map { String(format: "%4.1f", $0) } ?? "  - "
            return "\(b.rawValue) +\(l) dB (quiet \(String(format: "%5.1f", q)))"
        }.joined(separator: " | ")
    }

    private func handle(_ level: BoxLevel) {
        let t = now()
        direction.add(level, at: t)
        if t - lastLevelLog >= 0.5 {
            lastLevelLog = t
            Self.log.debug("levels \(self.levelsLine(at: t), privacy: .public) | streaming \(self.status.streamingBox?.rawValue ?? "-", privacy: .public)")
        }
        if let box = direction.updateStreamingBox(at: t) {
            Self.log.info("switch audio to \(box.rawValue, privacy: .public): \(self.levelsLine(at: t), privacy: .public)")
            source.streamAudio(from: box)
            status.streamingBox = box
        }
        status.loudness = Dictionary(uniqueKeysWithValues: BoxPosition.allCases.compactMap { b in
            direction.loudness(b, at: t).map { (b, $0) } })
        status.azimuthDeg = direction.azimuth(at: t)
        // Ages events out even while no audio arrives (box switched off, gated silence).
        if let snapshot = tracker.update(hits: [], azimuth: nil, levelDb: 0, now: Date()) {
            eventsOut.yield(snapshot)
        }
    }

    private func handle(_ frame: SoundFrame) {
        if let last = lastFrame, last.box == frame.box {
            let missed = BLESequence.missed(previous: last.seq, current: frame.seq)
            status.framesMissed += missed
            if missed > 0, missed <= maxFill {
                pending.append(contentsOf: repeatElement(0, count: missed * frame.samples.count))
            }
        }
        lastFrame = (frame.box, frame.seq)
        audioOut.yield(frame)
        status.framesReceived += 1
        pending.append(contentsOf: frame.samples.map { Float($0) / 32768 })

        let hop = detector.hopSamples
        while pending.count >= hop {
            let block = Array(pending.prefix(hop))
            pending.removeFirst(hop)
            step(block)
        }
    }

    private func step(_ block: [Float]) {
        let st = detector.process(block)
        let t = now()
        let az = direction.azimuth(at: t)
        let quiet = status.streamingBox.flatMap { direction.loudness($0, at: t) } ?? 0
        if let snapshot = tracker.update(hits: st.hits, azimuth: az, levelDb: quiet, now: Date()) {
            eventsOut.yield(snapshot)
        }
        direction.freezeQuietLevels(tracker.hasActiveUrgent)
        status.levelDb = st.levelDb
        status.gated = st.gated
        status.top3 = st.top3.map { (label: $0.0, prob: $0.1) }
        let speech = st.hits.contains { $0.label == "speech" }
        if status.speechActive, !speech { status.speechEnds += 1 }
        status.speechActive = speech
        status.azimuthDeg = az
        statusOut.yield(status)
    }
}
