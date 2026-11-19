import Foundation
import Models

// All-boxes detection, step 2 of 3 (docs/multi-sound.md): every box has its own `Detector`; this
// merges what the four of them report into one list of sounds, each with its own direction.

/// What one box's detector said on its newest update.
public struct BoxObservation: Sendable {
    public var hits: [Hit]
    /// The raw class probabilities; nil when the box was too quiet for the model to run.
    public var probs: [Float]?
    /// When it was observed (engine clock, seconds).
    public var at: Double
    public var levelDb: Double
    public var gated: Bool
    public var top3: [(String, Float)]

    public init(hits: [Hit], probs: [Float]?, at: Double, levelDb: Double, gated: Bool, top3: [(String, Float)]) {
        self.hits = hits
        self.probs = probs
        self.at = at
        self.levelDb = levelDb
        self.gated = gated
        self.top3 = top3
    }
}

public enum SourceFusion {
    /// An observation older than this is a box that went quiet or dropped out; it is ignored.
    public static let defaultMaxAgeS = 0.5

    /// One `Sighting` per sound class that any box's detector has fired, strongest first.
    ///
    /// - A class is present if ANY box fires it (each box's own persistence and "other" veto
    ///   already applied). The sighting keeps the best-scoring box's hit.
    /// - Its direction comes from `DirectionTracker.classDirection`, with each box's evidence for
    ///   the class = its raw probability squared (squaring favours the boxes that clearly hear it
    ///   over ones that only half hear it through another sound).
    /// - Two sounds of the same class at once (two dogs) are still one sighting.
    public static func fuse(observations: [BoxPosition: BoxObservation], names: [String],
                            direction: DirectionTracker, at t: Double,
                            maxAgeS: Double = defaultMaxAgeS) -> [Sighting] {
        let fresh = observations.filter { t - $0.value.at <= maxAgeS }
        var best: [String: Hit] = [:]
        for obs in fresh.values {
            for hit in obs.hits where hit.label != otherLabel {
                if hit.score > (best[hit.label]?.score ?? -Double.infinity) { best[hit.label] = hit }
            }
        }
        var out: [Sighting] = []
        for (label, hit) in best {
            guard let i = names.firstIndex(of: label) else { continue }
            var evidence: [BoxPosition: Float] = [:]
            for (box, obs) in fresh {
                if let p = obs.probs, i < p.count { evidence[box] = p[i] * p[i] }
            }
            let d = direction.classDirection(evidence: evidence, at: t)
            out.append(Sighting(hit: hit, azimuth: d.azimuthDeg, levelDb: d.levelDb ?? 0))
        }
        return out.sorted { $0.hit.score != $1.hit.score ? $0.hit.score > $1.hit.score : $0.hit.label < $1.hit.label }
    }
}
