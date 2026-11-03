import Foundation
import Testing
@testable import Detection
import Input
import Models

@Suite struct DirectionTests {
    /// Every box sits at -60 dBFS, then the sound comes up by the given dB per box.
    private func tracker(_ above: [BoxPosition: Float]) -> DirectionTracker {
        var d = DirectionTracker()
        for t in stride(from: 0.0, to: 2.0, by: 0.1) {
            for b in BoxPosition.allCases {
                d.add(BoxLevel(box: b, seq: 0, receivedAt: Date(), peakDbfs: -60, clipped: false), at: t)
            }
        }
        for b in BoxPosition.allCases {
            d.add(BoxLevel(box: b, seq: 0, receivedAt: Date(), peakDbfs: -60 + (above[b] ?? 0), clipped: false), at: 2.0)
        }
        return d
    }

    /// The worked example in docs/body-boxes-plan.md: FRONT 8, RIGHT 6, LEFT 2, BACK 1 -> ~30°.
    @Test func docExample() throws {
        let az = try #require(tracker([.front: 8, .right: 6, .left: 2, .back: 1]).azimuth(at: 2.0))
        #expect(abs(az - 29.7) < 0.5)
    }

    @Test func behindAndLeft() throws {
        #expect(try #require(tracker([.back: 12, .front: 2, .left: 3, .right: 3]).azimuth(at: 2.0)) == 180)
        #expect(abs(try #require(tracker([.left: 12, .right: 1, .front: 3, .back: 3]).azimuth(at: 2.0)) - 270) < 0.01)
    }

    /// FRONT and BACK nearly cancel (vector 1 dB < 3 dB): point at the loudest box instead.
    @Test func tinyVectorFallsBackToLoudestBox() throws {
        #expect(try #require(tracker([.front: 10, .back: 9]).azimuth(at: 2.0)) == 0)
        #expect(try #require(tracker([.back: 10, .front: 9]).azimuth(at: 2.0)) == 180)
    }

    @Test func quietOrSingleBoxIsUnclear() {
        #expect(tracker([.front: 1]).azimuth(at: 2.0) == nil)
        var one = DirectionTracker()
        one.add(BoxLevel(box: .front, seq: 0, receivedAt: Date(), peakDbfs: -60, clipped: false), at: 0)
        one.add(BoxLevel(box: .front, seq: 1, receivedAt: Date(), peakDbfs: -20, clipped: false), at: 0.1)
        #expect(one.azimuth(at: 0.1) == nil)
    }

    /// Switches only after another box is 3 dB louder for 0.3 s.
    @Test func streamingBoxHysteresis() {
        var d = DirectionTracker()
        func feed(_ t: Double, front: Float, back: Float) -> BoxPosition? {
            d.add(BoxLevel(box: .front, seq: 0, receivedAt: Date(), peakDbfs: front, clipped: false), at: t)
            d.add(BoxLevel(box: .back, seq: 0, receivedAt: Date(), peakDbfs: back, clipped: false), at: t)
            return d.updateStreamingBox(at: t)
        }
        #expect(feed(0.0, front: -60, back: -60) == .front)   // first box heard
        #expect(feed(0.1, front: -50, back: -60) == nil)
        // BACK louder by 2 dB: not enough
        for t in stride(from: 1.0, to: 2.0, by: 0.1) { #expect(feed(t, front: -50, back: -48) == nil) }
        // BACK louder by 6 dB: switches after 0.3 s, not before. (Peak hold keeps FRONT's -50 for
        // 0.3 s after it drops, so FRONT stays loud here on purpose.)
        var switched: Double?
        for t in stride(from: 2.0, to: 3.0, by: 0.1) where switched == nil {
            if feed(t, front: -50, back: -44) == .back { switched = t }
        }
        #expect(switched != nil && switched! >= 2.3 - 1e-9)
    }
}

@Suite struct EventTrackerTests {
    private func rules() throws -> LabelRules { try LabelRules.bundled() }

    @Test func startUpdateStop() throws {
        var tr = EventTracker(rules: try rules())
        let t0 = Date()
        let s1Raw = tr.update(hits: [Hit(label: "siren", conf: 0.9, score: 9)], azimuth: 180, levelDb: 12, now: t0)
        let s1 = try #require(s1Raw)
        #expect(s1.count == 1)
        let e = s1[0]
        #expect(e.label == .siren && e.isActive && e.isUrgent && e.categories == [.safety] && e.azimuthDeg == 180)
        let s2Raw = tr.update(hits: [Hit(label: "siren", conf: 0.95, score: 9)], azimuth: nil,
                                        levelDb: 14, now: t0.addingTimeInterval(0.5))
        let s2 = try #require(s2Raw)
        #expect(s2[0].id == e.id && s2[0].confidence == 0.95 && s2[0].azimuthDeg == 180)
        #expect(tr.update(hits: [], azimuth: nil, levelDb: 0, now: t0.addingTimeInterval(1.0)) == nil)   // within release
        let s3Raw = tr.update(hits: [], azimuth: nil, levelDb: 0, now: t0.addingTimeInterval(1.6))
        let s3 = try #require(s3Raw)
        #expect(s3.count == 1 && !s3[0].isActive)
        let s4Raw = tr.update(hits: [], azimuth: nil, levelDb: 0, now: t0.addingTimeInterval(4.0))
        let s4 = try #require(s4Raw)
        #expect(s4.isEmpty)
    }

    @Test func otherAndCategories() throws {
        var tr = EventTracker(rules: try rules())
        #expect(tr.update(hits: [Hit(label: "other", conf: 0.9, score: 1)], azimuth: nil, levelDb: 0, now: Date()) == nil)
        let sRaw = tr.update(hits: [Hit(label: "speech", conf: 0.9, score: 1),
                                              Hit(label: "dog", conf: 0.5, score: 1)],
                                       azimuth: nil, levelDb: 0, now: Date())
        let s = try #require(sRaw)
        let speech = try #require(s.first { $0.label == .speech })
        #expect(speech.categories == [.privacy] && !speech.isUrgent)
        #expect(try #require(s.first { $0.label == .dog }).categories.isEmpty)
    }
}

/// The whole Lane 2 path on a fixture clip: WavFileBoxSource (ADPCM like a box) -> DetectionEngine
/// -> SoundEvents, with recorded probabilities standing in for the model on a Mac.
@Suite struct EngineTests {
    @Test func engineEmitsEventFromBoxSource() async throws {
        let m = try loadManifest().detector
        let id = try #require(fixtureClipIDs.first { $0.contains("_siren_") })
        let (clip, audio) = try loadClip(id)
        let cls = StepReplayClassifier(labels: m.labels, thresholds: m.labels.map { Float(m.thresholds[$0]!) },
                                       probs: clip.steps.compactMap { $0.probs?.map(Float.init) })
        let samples = audio.map { Int16(max(-32768, min(32767, ($0 * 32768).rounded()))) }
        let src = WavFileBoxSource(samples: samples, loop: false, realTime: false)
        let engine = DetectionEngine(source: src, classifier: cls, rules: try LabelRules.bundled())
        let run = Task { await engine.run() }
        // Not real time: pick the box up front, or frames before the engine's first switch are dropped.
        src.streamAudio(from: .front)
        src.start()
        var labels = Set<SoundLabel>()
        for await snapshot in engine.activeEvents { labels.formUnion(snapshot.map(\.label)) }
        await run.value
        #expect(labels.contains(.siren))
    }
}

/// Returns recorded probability vectors in order, one per call.
final class StepReplayClassifier: SoundClassifier, @unchecked Sendable {
    let labels: [String]
    let thresholds: [Float]
    private var queue: [[Float]]

    init(labels: [String], thresholds: [Float], probs: [[Float]]) {
        self.labels = labels
        self.thresholds = thresholds
        queue = probs
    }

    func probs(window: [Float]) -> [Float] {
        queue.isEmpty ? [Float](repeating: 0, count: labels.count) : queue.removeFirst()
    }
}
