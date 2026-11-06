import Foundation
import Models

/// label -> categories and urgency, from Resources/categories.json (data, not code).
public struct LabelRules: Sendable {
    public var categories: [String: Set<FilterCategory>]
    public var urgent: Set<String>

    public init(categories: [String: Set<FilterCategory>], urgent: Set<String>) {
        self.categories = categories
        self.urgent = urgent
    }

    public static func bundled() throws -> LabelRules {
        struct File: Decodable { let categories: [String: [String]]; let urgent: [String] }
        let url = Bundle.module.url(forResource: "categories", withExtension: "json")!
        let f = try JSONDecoder().decode(File.self, from: Data(contentsOf: url))
        var cats: [String: Set<FilterCategory>] = [:]
        for (cat, labels) in f.categories {
            guard let c = FilterCategory(rawValue: cat) else { continue }
            for l in labels { cats[l, default: []].insert(c) }
        }
        return LabelRules(categories: cats, urgent: Set(f.urgent))
    }
}

/// Turns the detector's per-update hits into `SoundEvent`s with a start, updates and a stop.
public struct EventTracker: Sendable {
    /// A sound counts as stopped after this long without a hit (the detector re-fires every 0.1 s
    /// while it lasts, but a single dropped update shouldn't end it).
    public var releaseS = 1.0
    /// Stopped events stay in the snapshot this long with isActive = false, so the UI can fade them.
    public var lingerS = 2.0
    /// A sound's direction only updates while it's within this many dB of its own recent peak.
    /// The detector keeps reporting a sound for ~1 s after it stops (YAMNet hears the last second),
    /// and during that tail the boxes only hear room noise, whose direction is random: live on
    /// 2026-11-05 a talker in front flipped to "behind" the moment he stopped.
    public var directionWithinDb: Float = 10
    /// The recent peak falls this fast (dB/s), so a sound that gets quieter for real (a talker
    /// walking away) still updates its direction after a moment.
    public var peakDecayDbPerS: Float = 3
    public let rules: LabelRules

    private var active: [SoundLabel: SoundEvent] = [:]
    private var peak: [SoundLabel: (db: Float, at: Date)] = [:]
    private var ended: [SoundEvent] = []

    public init(rules: LabelRules) { self.rules = rules }

    /// One detector update. Returns the new snapshot when anything changed, else nil.
    public mutating func update(hits: [Hit], azimuth: Float?, levelDb: Float, now: Date) -> [SoundEvent]? {
        var changed = false
        for hit in hits {
            guard let label = SoundLabel(rawValue: hit.label) else { continue }
            if var e = active[label] {
                let p = peak[label].map { max(levelDb, $0.db - peakDecayDbPerS * Float(now.timeIntervalSince($0.at))) } ?? levelDb
                peak[label] = (p, now)
                e.confidence = hit.conf
                if levelDb >= p - directionWithinDb { e.azimuthDeg = azimuth ?? e.azimuthDeg }
                e.levelDb = levelDb
                e.updatedAt = now
                active[label] = e
            } else {
                peak[label] = (levelDb, now)
                active[label] = SoundEvent(label: label, confidence: hit.conf, azimuthDeg: azimuth, levelDb: levelDb,
                                           startedAt: now, updatedAt: now, isActive: true,
                                           isUrgent: rules.urgent.contains(hit.label),
                                           categories: rules.categories[hit.label] ?? [])
            }
            changed = true
        }
        for (label, e) in active where now.timeIntervalSince(e.updatedAt) >= releaseS {
            var done = e
            done.isActive = false
            ended.append(done)
            active[label] = nil
            peak[label] = nil
            changed = true
        }
        let before = ended.count
        ended.removeAll { now.timeIntervalSince($0.updatedAt) >= releaseS + lingerS }
        changed = changed || ended.count != before
        return changed ? snapshot : nil
    }

    public var snapshot: [SoundEvent] {
        active.values.sorted { $0.startedAt < $1.startedAt } + ended
    }

    public var hasActiveUrgent: Bool { active.values.contains { $0.isUrgent } }
}
