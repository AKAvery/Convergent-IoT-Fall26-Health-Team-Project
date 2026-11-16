import Models
import SwiftUI

/// The four sound groups the screens use (Home "Today's Feed", Settings "Sounds to detect").
enum CueGroup: String, CaseIterable, Identifiable, Sendable {
    case urgent, traffic, speech, ambient
    var id: Self { self }

    var title: String { rawValue.capitalized }

    var color: Color {
        switch self {
        case .urgent: Theme.urgent
        case .traffic: Theme.traffic
        case .speech: Theme.speech
        case .ambient: Theme.ambient
        }
    }
}

/// One sound as the screens draw it: a chip on the dial, an arc in its direction, the Live card.
struct SoundCue: Identifiable, Equatable, Sendable {
    let id: String
    var title: String
    var kind: String? = nil              // e.g. "Voice", shown before the distance
    var symbol: String                   // SF Symbols name
    var group: CueGroup
    var label: SoundLabel? = nil         // the model class; nil for cues that aren't a detected sound
    var azimuthDeg: Double               // 0° ahead, clockwise (90° right, 180° behind)
    var distanceM: Double? = nil
    var directionText: String? = nil     // overrides the computed direction, e.g. "Behind you"

    var isUrgent: Bool { group == .urgent }
    var direction: String { directionText ?? CueDirection.name(azimuthDeg) }

    /// "Voice · 4 m · Left" on a chip.
    func detail(showDistance: Bool) -> String {
        var parts: [String] = []
        if let kind { parts.append(kind) }
        if showDistance, let d = distanceM { parts.append("\(Int(d.rounded())) m") }
        parts.append(direction)
        return parts.joined(separator: " · ")
    }

    /// "12 meters, front-right" on the Live card.
    func longDetail(showDistance: Bool) -> String {
        if showDistance, let d = distanceM { return "\(Int(d.rounded())) meters, \(direction.lowercased())" }
        return direction
    }
}

enum CueDirection {
    /// 8 sectors of 45°.
    static func name(_ deg: Double) -> String {
        let names = ["Front", "Front-right", "Right", "Behind-right",
                     "Behind", "Behind-left", "Left", "Front-left"]
        return names[Int((normalized(deg) + 22.5) / 45) % 8]
    }

    static func normalized(_ deg: Double) -> Double {
        let r = deg.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// -180..180, negative = left of ahead.
    static func signed(_ deg: Double) -> Double {
        let n = normalized(deg)
        return n > 180 ? n - 360 : n
    }

    /// Screen point at `radius` from `center` in direction `deg` (0° up, clockwise).
    static func point(_ center: CGPoint, _ radius: CGFloat, _ deg: Double) -> CGPoint {
        let a = deg * .pi / 180
        return CGPoint(x: center.x + radius * sin(a), y: center.y - radius * cos(a))
    }
}
