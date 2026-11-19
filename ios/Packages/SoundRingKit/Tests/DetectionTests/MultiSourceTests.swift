import Foundation
import Testing
@testable import Detection
import Input
import Models

/// All-boxes detection (docs/multi-sound.md): several sounds at once, each with its own arrow.

/// Every box sits at -60 dBFS for 5 s, then the sound(s) bring each box up by the given dB.
/// Returns the tracker and a time at which those levels are current.
private func room(_ above: [BoxPosition: Float]) -> (DirectionTracker, Double) {
    var d = DirectionTracker()
    var seq: UInt16 = 0
    for k in 0..<53 {
        let t = Double(k) / 10
        for b in BoxPosition.allCases {
            let db: Float = k < 50 ? -60 : -60 + (above[b] ?? 0)
            d.add(BoxLevel(box: b, seq: seq, receivedAt: Date(), peakDbfs: db, clipped: false), at: t)
        }
        seq &+= 1
    }
    return (d, 5.2)
}

/// A siren on the left and a baby crying behind: both loud at their own box, quieter elsewhere.
private let sirenLeftBabyBehind: [BoxPosition: Float] = [.left: 20, .back: 20, .front: 6, .right: 6]

/// Evidence as the fusion computes it: squared class probability per box.
private func evidence(_ p: [BoxPosition: Float]) -> [BoxPosition: Float] { p.mapValues { $0 * $0 } }

@Suite struct ClassDirectionTests {
    @Test func twoSoundsGetTheirOwnDirections() {
        let (d, t) = room(sirenLeftBabyBehind)
        let siren = d.classDirection(evidence: evidence([.left: 0.9, .back: 0.1, .front: 0.1, .right: 0.1]), at: t)
        let baby = d.classDirection(evidence: evidence([.back: 0.9, .left: 0.1, .front: 0.1, .right: 0.1]), at: t)
        #expect(Azimuth.difference(siren.azimuthDeg ?? -999, 270) < 20)   // left
        #expect(Azimuth.difference(baby.azimuthDeg ?? -999, 180) < 20)    // behind
        #expect(abs((siren.levelDb ?? 0) - 20) < 0.01 && abs((baby.levelDb ?? 0) - 20) < 0.01)
    }

    /// The single arrow of the old design lands between the two sounds, pointing at neither.
    @Test func oneArrowForBothSoundsWouldBeWrong() throws {
        let (d, t) = room(sirenLeftBabyBehind)
        let both = try #require(d.azimuth(at: t))
        #expect(Azimuth.difference(both, 270) > 30 && Azimuth.difference(both, 180) > 30)
    }

    /// One sound every box hears equally well: same arrow as the original tug of war.
    @Test func singleSoundMatchesTheOriginalDirection() throws {
        let (d, t) = room([.front: 8, .right: 6, .left: 2, .back: 1])   // body-boxes-plan.md example
        let all = evidence([.front: 0.9, .right: 0.9, .left: 0.9, .back: 0.9])
        let classWise = try #require(d.classDirection(evidence: all, at: t).azimuthDeg)
        let original = try #require(d.azimuth(at: t))
        #expect(abs(classWise - original) < 0.01)
        #expect(Azimuth.difference(classWise, 30) < 3)
    }

    @Test func noBoxHeardItMeansNoDirection() {
        let (d, t) = room(sirenLeftBabyBehind)
        let r = d.classDirection(evidence: [:], at: t)
        #expect(r.azimuthDeg == nil && r.levelDb == nil)
        let zero = d.classDirection(evidence: [.left: 0, .back: 0], at: t)
        #expect(zero.azimuthDeg == nil && zero.levelDb == nil)
    }

    @Test func barelyAboveQuietMeansNoDirection() {
        let (d, t) = room([.left: 1, .right: 1, .front: 1, .back: 1])
        let r = d.classDirection(evidence: evidence([.left: 0.9, .right: 0.9]), at: t)
        #expect(r.azimuthDeg == nil)
        #expect(abs((r.levelDb ?? 0) - 1) < 0.01)
    }

    /// Only the left box hears the class (the others are gated): points at the left box.
    @Test func oneBoxHearingItPointsAtThatBox() throws {
        let (d, t) = room([.left: 15, .right: 15, .front: 15, .back: 15])
        let az = try #require(d.classDirection(evidence: evidence([.left: 0.9]), at: t).azimuthDeg)
        #expect(Azimuth.difference(az, 270) < 1)
    }
}

@Suite struct SourceFusionTests {
    private let names = ["siren", "baby_cry", "other"]

    private func obs(hits: [Hit], probs: [Float]?, at t: Double) -> BoxObservation {
        BoxObservation(hits: hits, probs: probs, at: t, levelDb: -30, gated: probs == nil, top3: [])
    }

    private func observations(at t: Double) -> [BoxPosition: BoxObservation] {
        let siren = Hit(label: "siren", conf: 0.9, score: 9)
        let baby = Hit(label: "baby_cry", conf: 0.9, score: 7)
        return [
            .left: obs(hits: [siren], probs: [0.9, 0.1, 0], at: t),
            .back: obs(hits: [baby], probs: [0.1, 0.9, 0], at: t),
            .front: obs(hits: [], probs: [0.1, 0.1, 0.8], at: t),
            .right: obs(hits: [], probs: [0.1, 0.1, 0.8], at: t),
        ]
    }

    @Test func eachSoundGetsOneSightingWithItsOwnDirection() throws {
        let (d, t) = room(sirenLeftBabyBehind)
        let s = SourceFusion.fuse(observations: observations(at: t), names: names, direction: d, at: t)
        #expect(s.map(\.hit.label) == ["siren", "baby_cry"])   // strongest score first
        #expect(Azimuth.difference(try #require(s[0].azimuth), 270) < 20)
        #expect(Azimuth.difference(try #require(s[1].azimuth), 180) < 20)
    }

    /// The same sound heard on several boxes is one sighting, not four.
    @Test func sameSoundOnManyBoxesIsOneSighting() {
        let (d, t) = room([.left: 10, .right: 10, .front: 10, .back: 10])
        let siren = Hit(label: "siren", conf: 0.9, score: 9)
        let all = Dictionary(uniqueKeysWithValues: BoxPosition.allCases.map {
            ($0, obs(hits: [siren], probs: [0.9, 0, 0], at: t))
        })
        let s = SourceFusion.fuse(observations: all, names: names, direction: d, at: t)
        #expect(s.count == 1 && s[0].hit.label == "siren")
    }

    @Test func staleBoxesAreIgnoredAndOtherIsNeverASound() {
        let (d, t) = room(sirenLeftBabyBehind)
        #expect(SourceFusion.fuse(observations: observations(at: t - 2), names: names, direction: d, at: t).isEmpty)
        let other = [BoxPosition.left: obs(hits: [Hit(label: "other", conf: 0.9, score: 1)], probs: [0, 0, 0.9], at: t)]
        #expect(SourceFusion.fuse(observations: other, names: names, direction: d, at: t).isEmpty)
    }

    @Test func eventTrackerKeepsEachSoundsOwnDirection() throws {
        let (d, t) = room(sirenLeftBabyBehind)
        let sightings = SourceFusion.fuse(observations: observations(at: t), names: names, direction: d, at: t)
        var tr = EventTracker(rules: try LabelRules.bundled())
        let snapshot = try #require(tr.update(sightings: sightings, now: Date()))
        let siren = try #require(snapshot.first { $0.label == .siren })
        let baby = try #require(snapshot.first { $0.label == .babyCry })
        #expect(Azimuth.difference(try #require(siren.azimuthDeg), 270) < 20)
        #expect(Azimuth.difference(try #require(baby.azimuthDeg), 180) < 20)
        #expect(siren.isUrgent)
    }
}

/// Returns the same probabilities for every window, from whichever box.
final class FixedClassifier: SoundClassifier, @unchecked Sendable {
    let labels: [String]
    let thresholds: [Float]
    private let p: [Float]

    init(labels: [String], thresholds: [Float], probs: [Float]) {
        self.labels = labels
        self.thresholds = thresholds
        p = probs
    }

    func probs(window: [Float]) -> [Float] { p }
}

@Suite struct AllBoxesEngineTests {
    /// The whole path: 4 boxes' audio -> 4 detectors -> fusion -> events. Two sounds the classifier
    /// reports at once both come out as separate events.
    @Test func overlappingSoundsBothBecomeEvents() async throws {
        let m = try loadManifest().detector
        let id = try #require(fixtureClipIDs.first { $0.contains("_siren_") })
        let (_, audio) = try loadClip(id)
        var p = [Float](repeating: 0, count: m.labels.count)
        let iSiren = try #require(m.labels.firstIndex(of: "siren"))
        let iBaby = try #require(m.labels.firstIndex(of: "baby_cry"))
        p[iSiren] = 0.95
        p[iBaby] = 0.95
        let cls = FixedClassifier(labels: m.labels, thresholds: m.labels.map { Float(m.thresholds[$0]!) }, probs: p)
        let samples = audio.map { Int16(max(-32768, min(32767, ($0 * 32768).rounded()))) }
        let src = WavFileBoxSource(samples: samples, loop: false, realTime: false)
        let engine = DetectionEngine(source: src, classifier: cls, rules: try LabelRules.bundled(), mode: .allBoxes)
        let run = Task { await engine.run() }
        // Not real time: ask for all boxes up front, or frames before the engine's first call are dropped.
        src.streamAudio(from: Set(BoxPosition.allCases))
        src.start()
        var labels = Set<SoundLabel>()
        for await snapshot in engine.activeEvents { labels.formUnion(snapshot.map(\.label)) }
        await run.value
        #expect(labels.isSuperset(of: [.siren, .babyCry]))
    }
}
