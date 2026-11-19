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

/// How the engine uses the boxes' audio.
public enum DetectionMode: Sendable {
    /// One audio stream, from the loudest box, one detector. Cheapest on Bluetooth and battery;
    /// overlapping sounds share one arrow (the original design, docs/body-boxes-plan.md).
    case loudestBox
    /// All 4 boxes stream, each with its own detector; every sound gets its own arrow and level.
    /// Most accurate for overlapping sounds (docs/multi-sound.md); about 4x the Bluetooth and
    /// model work.
    case allBoxes
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
    private let mode: DetectionMode
    // All-boxes mode only: one detector, audio buffer, packet counter and newest result per box.
    private let boxDetectors: [BoxPosition: Detector]
    private var pendingByBox: [BoxPosition: [Float]] = [:]
    private var lastSeqByBox: [BoxPosition: UInt16] = [:]
    private var observations: [BoxPosition: BoxObservation] = [:]
    private var direction: DirectionTracker
    private var tracker: EventTracker
    private var pending: [Float] = []
    /// Loudness (dBFS) of the newest hops, for the early end-of-speech check below.
    private var hopDb: [Double] = []
    /// The early check already reported the end of the current speech.
    private var endedEarly = false
    private var lastFrame: (box: BoxPosition, seq: UInt16)?
    private var status = DetectionStatus()
    private let t0 = Date()

    /// Missing audio packets up to this many are filled with silence to keep timing; longer gaps
    /// (a box switch, a drop-out) just continue.
    private let maxFill = 10

    public init(source: any BoxSource & Sendable, classifier: any SoundClassifier,
                params: DetectorParams = DetectorParams(), rules: LabelRules,
                direction: DirectionConfig = DirectionConfig(), mode: DetectionMode = .loudestBox) {
        self.source = source
        self.mode = mode
        self.detector = Detector(params: params, classifier: classifier, preset: "all")
        // The detectors share one classifier: the engine is an actor, so they never run at once.
        self.boxDetectors = Dictionary(uniqueKeysWithValues: BoxPosition.allCases.map {
            ($0, Detector(params: params, classifier: classifier, preset: "all"))
        })
        self.direction = DirectionTracker(config: direction)
        self.tracker = EventTracker(rules: rules)
        (activeEvents, eventsOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (statusUpdates, statusOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
        (audioFrames, audioOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(250))
    }

    /// Runs until the task is cancelled or the source finishes.
    public func run() async {
        // All-boxes mode: ask every box for audio up front. A box that connects later starts as
        // soon as its audio subscription is on.
        if mode == .allBoxes { source.streamAudio(from: Set(BoxPosition.allCases)) }
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
        if mode == .allBoxes {
            status.streamingBox = direction.loudestBox(at: t)?.box   // the lead box; every box streams
        } else if let box = direction.updateStreamingBox(at: t) {
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
        if mode == .allBoxes { handleAllBoxes(frame); return }
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

    /// The detector's `speech` hit stays on for about a second after the voice stops (YAMNet hears
    /// the last 0.975 s), so the name listener was told "speech ended" about a second late. This
    /// looks at the newest hops directly: the last `quietHops` are all `dropDb` below the loudest of
    /// the `baselineHops` before them. The detector's own end stays as the fallback (loud rooms,
    /// where the voice never drops that far).
    private static let baselineHops = 6
    private static let quietHops = 4
    private static let dropDb = 12.0

    private func voiceDropped() -> Bool {
        guard hopDb.count == Self.baselineHops + Self.quietHops,
              let before = hopDb.prefix(Self.baselineHops).max() else { return false }
        return hopDb.suffix(Self.quietHops).allSatisfy { $0 < before - Self.dropDb }
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
        trackSpeech(speech: st.hits.contains { $0.label == "speech" }, hop: block)
        status.azimuthDeg = az
        statusOut.yield(status)
    }

    /// Speech start/stop bookkeeping. `hop` is the newest audio of the stream the end-of-speech
    /// loudness check should watch; nil leaves that history alone (all-boxes mode passes only the
    /// lead box's audio).
    private func trackSpeech(speech: Bool, hop: [Float]?) {
        if let hop {
            let power = hop.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(hop.count, 1))
            hopDb.append(dbfs(power.squareRoot()))
            if hopDb.count > Self.baselineHops + Self.quietHops { hopDb.removeFirst() }
        }
        if status.speechActive, !speech {
            if !endedEarly { status.speechEnds += 1 }
            endedEarly = false
        } else if speech, !endedEarly, voiceDropped() {
            status.speechEnds += 1
            endedEarly = true
        }
        status.speechActive = speech
    }

    // MARK: - All-boxes mode (docs/multi-sound.md)

    /// Fresh result of a box newer than this counts; older = the box went quiet or dropped out.
    private static let observationMaxAgeS = SourceFusion.defaultMaxAgeS

    /// Audio from any box goes into that box's own buffer and detector.
    private func handleAllBoxes(_ frame: SoundFrame) {
        let box = frame.box
        if let prev = lastSeqByBox[box] {
            let missed = BLESequence.missed(previous: prev, current: frame.seq)
            status.framesMissed += missed
            if missed > 0, missed <= maxFill {
                pendingByBox[box, default: []].append(contentsOf: repeatElement(0, count: missed * frame.samples.count))
            }
        }
        lastSeqByBox[box] = frame.seq
        // Name alerts listen to one stream: the lead (loudest) box, like the single-stream mode.
        if status.streamingBox == nil || status.streamingBox == box { audioOut.yield(frame) }
        status.framesReceived += 1
        pendingByBox[box, default: []].append(contentsOf: frame.samples.map { Float($0) / 32768 })

        guard let det = boxDetectors[box] else { return }
        let hop = det.hopSamples
        while (pendingByBox[box]?.count ?? 0) >= hop {
            let block = Array(pendingByBox[box, default: []].prefix(hop))
            pendingByBox[box]?.removeFirst(hop)
            stepAllBoxes(block, from: box)
        }
    }

    /// One 0.1 s hop from one box: that box's detector runs, then the four boxes' newest results
    /// are fused into one `Sighting` per sound, each with its own direction.
    private func stepAllBoxes(_ block: [Float], from box: BoxPosition) {
        guard let det = boxDetectors[box] else { return }
        let st = det.process(block)
        let t = now()
        observations[box] = BoxObservation(hits: st.hits, probs: st.probs, at: t, levelDb: st.levelDb,
                                           gated: st.gated, top3: st.top3)
        let sightings = SourceFusion.fuse(observations: observations, names: det.names,
                                          direction: direction, at: t, maxAgeS: Self.observationMaxAgeS)
        if let snapshot = tracker.update(sightings: sightings, now: Date()) {
            eventsOut.yield(snapshot)
        }
        direction.freezeQuietLevels(tracker.hasActiveUrgent)

        // The status line follows the box that hears the most right now.
        let lead = observations.values
            .filter { t - $0.at <= Self.observationMaxAgeS && !$0.gated }
            .max { $0.levelDb < $1.levelDb }
        status.gated = lead == nil
        status.levelDb = lead?.levelDb ?? st.levelDb
        status.top3 = (lead?.top3 ?? st.top3).map { (label: $0.0, prob: $0.1) }
        let primary = direction.loudestBox(at: t)?.box ?? box
        trackSpeech(speech: sightings.contains { $0.hit.label == "speech" }, hop: box == primary ? block : nil)
        status.azimuthDeg = sightings.first?.azimuth ?? direction.azimuth(at: t)
        statusOut.yield(status)
    }
}
