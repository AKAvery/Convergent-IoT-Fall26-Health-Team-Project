import Foundation
import Testing
@testable import Detection
import Models

/// Simulated rooms for the audio-stream box choice: several sources, each heard at every box with
/// some body shadow, one `level` per box every 100 ms like the firmware. Sources add as power.
private struct Room {
    struct Source {
        /// dB above the quiet level at each box while the source is on.
        var gains: [BoxPosition: Float]
        /// [start, end) seconds when it's on.
        var on: [(Double, Double)]
    }

    var sources: [Source] = []
    var quietDbfs: Float = -60
    var jitterDb: Float = 1.5
    private var rng: UInt64 = 0x9E3779B97F4A7C15

    init(_ sources: [Source]) { self.sources = sources }

    mutating func noise() -> Float {
        rng = rng &* 6364136223846793005 &+ 1442695040888963407
        return (Float(rng >> 40) / Float(1 << 24) * 2 - 1) * jitterDb
    }

    mutating func level(_ box: BoxPosition, at t: Double) -> Float {
        var power: Float = 1                                       // the quiet level itself
        for s in sources where s.on.contains(where: { t >= $0.0 && t < $0.1 }) {
            power += pow(10, (s.gains[box] ?? 0) / 10)
        }
        return quietDbfs + 10 * log10(power) + noise()
    }

    /// Runs `tracker` from 0 to `until`; returns every switch (time, box) after the first pick.
    /// Like the app (DetectionEngine.handle): the boxes' packets arrive 25 ms apart and the
    /// stream choice runs after each one, so it sometimes compares a fresh level with ones up
    /// to 100 ms old. Deciding once after all 4 boxes hid a wrong-box bug in the fast lane.
    mutating func run(_ tracker: inout DirectionTracker, until: Double) -> [(t: Double, box: BoxPosition)] {
        var switches: [(Double, BoxPosition)] = []
        var first = true
        for k in 0..<Int(until * 10) {
            for (i, b) in BoxPosition.allCases.enumerated() {
                let t = Double(k) / 10 + Double(i) * 0.025
                tracker.add(BoxLevel(box: b, seq: UInt16(truncatingIfNeeded: k), receivedAt: Date(),
                                     peakDbfs: level(b, at: t), clipped: false), at: t)
                if let box = tracker.updateStreamingBox(at: t) {
                    if first { first = false } else { switches.append((t, box)) }
                }
            }
        }
        return switches
    }
}

/// A talker facing one box: loudest there, ~8 dB of body shadow on the far side.
private func talker(at box: BoxPosition, db: Float = 20, seed: UInt64, until: Double) -> Room.Source {
    let opposite: [BoxPosition: BoxPosition] = [.front: .back, .back: .front, .left: .right, .right: .left]
    var gains: [BoxPosition: Float] = [:]
    for b in BoxPosition.allCases { gains[b] = b == box ? db : b == opposite[box] ? db - 8 : db - 5 }
    // Syllables and words: on 0.15-0.6 s, gaps 0.05-0.4 s.
    var on: [(Double, Double)] = []
    var r = seed
    func next() -> Double { r = r &* 6364136223846793005 &+ 1442695040888963407; return Double(r >> 11) / Double(1 << 53) }
    var t = next() * 0.3
    while t < until {
        let len = 0.15 + next() * 0.45
        on.append((t, t + len))
        t += len + 0.05 + next() * 0.35
    }
    return Room.Source(gains: gains, on: on)
}

/// The rule on main before this branch: 1 s average, 3 dB for 0.5 s, no cooldown.
private var mainRule: DirectionConfig {
    var c = DirectionConfig()
    c.switchCooldownS = 0
    return c
}

@Suite struct StreamSwitchingScenarioTests {
    /// Two people at the same volume, one in front and one behind, talking over each other for
    /// 60 s. Which box streams barely matters (both are "speech"); it must not ping-pong.
    @Test(arguments: [(BoxPosition.front, BoxPosition.back), (.left, .right), (.front, .right)])
    func twoEqualTalkers(_ a: BoxPosition, _ b: BoxPosition) {
        let sources = [talker(at: a, seed: 1, until: 60), talker(at: b, seed: 2, until: 60)]
        var oldRoom = Room(sources), newRoom = Room(sources)
        var old = DirectionTracker(config: mainRule), new = DirectionTracker()
        let before = oldRoom.run(&old, until: 60), after = newRoom.run(&new, until: 60)
        print("two talkers \(a.rawValue)+\(b.rawValue), 60 s: main \(before.count) switches, branch \(after.count)")
        #expect(after.count <= before.count)
        #expect(after.count <= 6, "\(after.map { "\($0.t)s->\($0.box.rawValue)" })")
        for (x, y) in zip(after, after.dropFirst()) { #expect(y.t - x.t >= 1.5 - 1e-9) }
    }

    /// Two people taking turns (1-3 s each, a little overlap), one 2 dB quieter. Following each
    /// turn is fine; switching faster than every 1.5 s is not.
    @Test func turnTaking() {
        var r: UInt64 = 7
        func next() -> Double { r = r &* 6364136223846793005 &+ 1442695040888963407; return Double(r >> 11) / Double(1 << 53) }
        var aOn: [(Double, Double)] = [], bOn: [(Double, Double)] = []
        var t = 0.5, aTurn = true
        while t < 60 {
            let len = 0.6 + next() * 2.4
            if aTurn { aOn.append((t, t + len)) } else { bOn.append((t, t + len)) }
            t += len - next() * 0.4                              // next talker starts a bit early
            aTurn.toggle()
        }
        var a = talker(at: .front, seed: 8, until: 60), b = talker(at: .left, db: 18, seed: 9, until: 60)
        // Talk only during your turn (syllables inside the turn).
        a.on = a.on.filter { s in aOn.contains { s.0 >= $0.0 && s.0 < $0.1 } }
        b.on = b.on.filter { s in bOn.contains { s.0 >= $0.0 && s.0 < $0.1 } }
        var oldRoom = Room([a, b]), newRoom = Room([a, b])
        var old = DirectionTracker(config: mainRule), new = DirectionTracker()
        let before = oldRoom.run(&old, until: 60), after = newRoom.run(&new, until: 60)
        let fastest = { (s: [(t: Double, box: BoxPosition)]) in zip(s, s.dropFirst()).map { $1.t - $0.t }.min() ?? .infinity }
        print("turn taking, \(aOn.count + bOn.count) turns in 60 s: main \(before.count) switches (closest \(fastest(before)) s), branch \(after.count) (closest \(fastest(after)) s)")
        #expect(fastest(after) >= 1.5 - 1e-9)
    }

    /// The arrow (not the stream): two people talking at once, front and right. Today's single
    /// tug-of-war arrow jumps between them. Phase 2-3 (per-band votes + one track per talker) is
    /// the fix; this records the size of the problem until then.
    @Test func arrowFlickersWithTwoTalkers() {
        var room = Room([talker(at: .front, seed: 11, until: 60), talker(at: .right, seed: 12, until: 60)])
        var d = DirectionTracker()
        _ = room.run(&d, until: 0.1)
        var last: Float?, jumps = 0, readings = 0
        for k in 1..<600 {
            let t = Double(k) / 10
            for b in BoxPosition.allCases {
                d.add(BoxLevel(box: b, seq: 0, receivedAt: Date(), peakDbfs: room.level(b, at: t), clipped: false), at: t)
            }
            guard let az = d.azimuth(at: t) else { continue }
            readings += 1
            if let l = last, abs(Azimuth.normalized(az - l + 180) - 180) >= 30 { jumps += 1 }
            last = az
        }
        print("arrow, two talkers front+right, 60 s: \(jumps) jumps of 30°+ in \(readings) readings")
        withKnownIssue("one arrow can't show two talkers: needs per-band votes + tracks (Phase 2-3)") {
            #expect(jumps <= 6)
        }
    }

    /// Four people around the wearer, all talking: no faster than one switch per 1.5 s.
    @Test func fourTalkers() {
        let sources = BoxPosition.allCases.enumerated().map { talker(at: $1, seed: UInt64($0 + 10), until: 60) }
        var oldRoom = Room(sources), newRoom = Room(sources)
        var old = DirectionTracker(config: mainRule), new = DirectionTracker()
        let before = oldRoom.run(&old, until: 60), after = newRoom.run(&new, until: 60)
        print("four talkers, 60 s: main \(before.count) switches, branch \(after.count)")
        #expect(after.count <= before.count)
        #expect(after.count <= 8)
    }

    /// Regression for the fast lane (removed): someone in FRONT talks, stops, and 3 s later
    /// someone BEHIND starts. With packets 25 ms apart, a side box that reported first looked
    /// like a sudden sound and took the stream for ~3 s while it was 5 dB down on the talker.
    /// The stream must only ever be on the talker's box.
    @Test func newTalkerAfterPauseStreamsTheirBox() {
        let front = Room.Source(gains: [.front: 20, .back: 12, .left: 15, .right: 15],
                                on: stride(from: 0.25, to: 6, by: 0.75).map { ($0, $0 + 0.5) })
        let back = Room.Source(gains: [.back: 20, .front: 12, .left: 15, .right: 15],
                               on: stride(from: 9.25, to: 20, by: 0.75).map { ($0, $0 + 0.5) })
        var room = Room([front, back])
        room.jitterDb = 0
        var d = DirectionTracker()
        let s = room.run(&d, until: 20)
        print("talker front, pause, talker back: \(s.map { "\($0.t)s->\($0.box.rawValue)" })")
        #expect(s.allSatisfy { $0.box == .back }, "\(s.map { "\($0.t)s->\($0.box.rawValue)" })")
        #expect(d.streamingBox == .back)
    }

    /// Handling noise: a thump on the BACK box only (the others don't hear it). No switch.
    @Test func thumpOnOneBoxIgnored() {
        let speech = talker(at: .front, db: 15, seed: 6, until: 10)
        let thump = Room.Source(gains: [.back: 30], on: [(4.0, 4.3), (7.0, 7.2)])
        var room = Room([speech, thump])
        var d = DirectionTracker()
        let s = room.run(&d, until: 10)
        // (The first pick at t = 0 is a coin toss in silence; after 2 s it must be FRONT and stay.)
        #expect(d.streamingBox == .front)
        #expect(!s.contains { $0.t >= 2 }, "\(s.map { "\($0.t)s->\($0.box.rawValue)" })")
    }
}
