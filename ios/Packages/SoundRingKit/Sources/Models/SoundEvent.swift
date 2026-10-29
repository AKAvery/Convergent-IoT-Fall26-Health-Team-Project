import Foundation

// Contract 3 in docs/team-plan.md: Lane 2 (Detection) -> Lanes 3 and 4.

/// Raw values are the class names in `ml/models/labels.json`, so they match the model and
/// the Python code. The model's 13th class, `other`, is deliberately not a case: it is never
/// shown to the user, so `SoundLabel(rawValue: "other")` is nil.
public enum SoundLabel: String, Codable, CaseIterable, Sendable {
    case siren, alarm
    case glassBreak = "glass_break"
    case carHorn = "car_horn"
    case babyCry = "baby_cry"
    case knock, clap, dog, cat, appliance, speech, footsteps
}

public enum FilterCategory: String, Codable, Sendable {
    case safety, privacy, babies
}

public struct SoundEvent: Identifiable, Codable, Sendable {
    public let id: UUID
    public let label: SoundLabel
    public var confidence: Float     // 0–1
    public var azimuthDeg: Float?    // see Azimuth; nil if direction is unclear
    public var levelDb: Float        // dB above the loudest box's quiet level
    public let startedAt: Date
    public var updatedAt: Date
    public var isActive: Bool        // false once the sound has stopped
    public var isUrgent: Bool        // alert + buzz even if the app is in the background
    public var categories: Set<FilterCategory>

    public init(
        id: UUID = UUID(),
        label: SoundLabel,
        confidence: Float,
        azimuthDeg: Float?,
        levelDb: Float,
        startedAt: Date,
        updatedAt: Date,
        isActive: Bool,
        isUrgent: Bool,
        categories: Set<FilterCategory>
    ) {
        self.id = id
        self.label = label
        self.confidence = confidence
        self.azimuthDeg = azimuthDeg
        self.levelDb = levelDb
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.isActive = isActive
        self.isUrgent = isUrgent
        self.categories = categories
    }
}

public protocol SoundEventSource {
    var activeEvents: AsyncStream<[SoundEvent]> { get }   // full snapshot on every change
}
