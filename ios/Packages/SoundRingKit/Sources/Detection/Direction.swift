import Foundation
import Models

// Direction from body shadow (docs/body-boxes-plan.md): each box's loudness above its own quiet
// level, peak-held over 0.3 s, then a tug of war: angle = atan2(RIGHT - LEFT, FRONT - BACK).

public struct DirectionConfig: Sendable {
    /// Quiet level = the quietest the box has been over this long.
    public var quietWindowS = 10.0
    /// Each box reports its peak over this long, so a clap still counts.
    public var peakHoldS = 0.3
    /// Below this tug-of-war length (dB) the arrow points at the loudest box instead.
    public var minVectorDb: Float = 3
    /// No box this far above its quiet level: direction unclear.
    public var minLoudnessDb: Float = 3
    /// A box with no `level` for this long is ignored.
    public var staleS = 1.0
    /// Switch the audio stream when another box's average loudness over `switchAverageS` is
    /// louder by this much ...
    public var switchMarginDb: Float = 3
    /// ... for this long.
    public var switchHoldS = 0.5
    /// The audio-stream choice uses each box's average over this long, not the 0.3 s peak: live
    /// on 2026-11-05 (boxes on chest and back, talker in front) single handling thumps and
    /// rumble peaks switched the stream 10 times in 30 s.
    public var switchAverageS = 1.0
    /// After any switch, wait this long before switching again, so two talkers at about the same
    /// volume can't trade the stream back and forth. Like the "last mic hold" in Jitsi's
    /// dominant-speaker code and broadcast automixers.
    public var switchCooldownS = 1.5

    public init() {}
}

/// Tracks the 4 boxes' levels. Feed every `BoxLevel`; ask for the direction and the loudest box.
public struct DirectionTracker: Sendable {
    public let config: DirectionConfig
    private var history: [BoxPosition: [(t: Double, db: Float)]] = [:]
    private var frozenQuiet: [BoxPosition: Float]?
    private var candidate: (box: BoxPosition, since: Double)?
    private var lastSwitchT = -Double.infinity
    public private(set) var streamingBox: BoxPosition?

    public init(config: DirectionConfig = DirectionConfig()) { self.config = config }

    public mutating func add(_ level: BoxLevel, at t: Double) {
        var h = history[level.box] ?? []
        h.append((t, level.peakDbfs))
        let cutoff = t - config.quietWindowS
        if let first = h.firstIndex(where: { $0.t >= cutoff }), first > 0 { h.removeFirst(first) }
        history[level.box] = h
    }

    /// While a long safety sound plays, keep the quiet levels from before it, or a 10 s siren
    /// would become the new "quiet".
    public mutating func freezeQuietLevels(_ freeze: Bool) {
        if freeze, frozenQuiet == nil {
            frozenQuiet = Dictionary(uniqueKeysWithValues: BoxPosition.allCases.compactMap { b in quietRaw(b).map { (b, $0) } })
        } else if !freeze {
            frozenQuiet = nil
        }
    }

    private func quietRaw(_ box: BoxPosition) -> Float? { history[box]?.map(\.db).min() }

    public func quietLevel(_ box: BoxPosition) -> Float? { frozenQuiet?[box] ?? quietRaw(box) }

    /// dB above the box's quiet level, peak-held; nil if the box is silent or stale.
    public func loudness(_ box: BoxPosition, at t: Double) -> Float? {
        guard let h = history[box], let last = h.last, t - last.t <= config.staleS,
              let quiet = quietLevel(box) else { return nil }
        let held = h.reversed().prefix { t - $0.t <= config.peakHoldS }.map(\.db).max() ?? last.db
        return max(0, held - quiet)
    }

    public func loudestBox(at t: Double) -> (box: BoxPosition, db: Float)? {
        BoxPosition.allCases.compactMap { b in loudness(b, at: t).map { (b, $0) } }.max { $0.1 < $1.1 }
    }

    /// dB above the box's quiet level, averaged over `switchAverageS`; nil if silent or stale.
    public func averageLoudness(_ box: BoxPosition, at t: Double) -> Float? {
        guard let h = history[box], let last = h.last, t - last.t <= config.staleS,
              let quiet = quietLevel(box) else { return nil }
        let recent = h.reversed().prefix { t - $0.t <= config.switchAverageS }.map { max(0, $0.db - quiet) }
        return recent.isEmpty ? nil : recent.reduce(0, +) / Float(recent.count)
    }

    /// Azimuth in the team convention, or nil when no box is clearly above its quiet level or
    /// only one box is reporting (one box can't tell direction).
    public func azimuth(at t: Double) -> Float? {
        let l = Dictionary(uniqueKeysWithValues: BoxPosition.allCases.compactMap { b in loudness(b, at: t).map { (b, $0) } })
        guard l.count >= 2, let loudest = l.max(by: { $0.value < $1.value }),
              loudest.value >= config.minLoudnessDb else { return nil }
        let sideways = (l[.right] ?? 0) - (l[.left] ?? 0)
        let forward = (l[.front] ?? 0) - (l[.back] ?? 0)
        if (sideways * sideways + forward * forward).squareRoot() < config.minVectorDb {
            return loudest.key.facingDeg
        }
        return Azimuth.normalized(atan2(sideways, forward) * 180 / .pi)
    }

    /// The box that should stream audio. Switches only when another box's 1 s average has been
    /// louder by `switchMarginDb` for `switchHoldS`, and at least `switchCooldownS` after the last
    /// switch, so the stream doesn't flip back and forth.
    /// Returns the new box when it changes.
    public mutating func updateStreamingBox(at t: Double) -> BoxPosition? {
        guard let (top, topDb) = BoxPosition.allCases.compactMap({ b in averageLoudness(b, at: t).map { (b, $0) } })
            .max(by: { $0.1 < $1.1 }) else { return nil }
        guard let current = streamingBox else { return switchTo(top, at: t) }

        let currentDb = averageLoudness(current, at: t)
        if top != current, currentDb == nil || topDb >= currentDb! + config.switchMarginDb {
            if candidate?.box != top { candidate = (top, t) }
            if currentDb == nil
                || (t - candidate!.since >= config.switchHoldS && t - lastSwitchT >= config.switchCooldownS) {
                return switchTo(top, at: t)
            }
        } else {
            candidate = nil
        }
        return nil
    }

    private mutating func switchTo(_ box: BoxPosition, at t: Double) -> BoxPosition {
        streamingBox = box
        candidate = nil
        lastSwitchT = t
        return box
    }
}
