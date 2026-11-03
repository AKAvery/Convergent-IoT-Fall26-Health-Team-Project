import Foundation

/// The example content shown in the Figma screens. Every screen reads from here until real data
/// is wired in, so swapping it out is one place.
enum DemoData {
    static let carHorn = SoundCue(id: "car-horn", title: "Car horn", symbol: "car.fill", group: .urgent,
                                  azimuthDeg: 40, distanceM: 12)
    static let heyAlex = SoundCue(id: "hey-alex", title: "\u{201C}Hey, Alex!\u{201D}", kind: "Voice",
                                  symbol: "bubble.left.fill", group: .speech, azimuthDeg: 292, distanceM: 4)
    static let dogBark = SoundCue(id: "dog-bark", title: "Dog bark", symbol: "dog.fill", group: .ambient,
                                  azimuthDeg: 250, distanceM: 18)
    static let bikeBell = SoundCue(id: "bike-bell", title: "Bike bell", symbol: "bell.fill", group: .traffic,
                                   azimuthDeg: 178, distanceM: 6)

    /// Live view and the Profile feed post.
    static let liveScene = [carHorn, heyAlex, dogBark, bikeBell]

    /// Welcome screen and Watch.
    static let welcomeScene = [
        carHorn,
        SoundCue(id: "hey", title: "\u{201C}Hey!\u{201D}", symbol: "bubble.left.fill", group: .speech,
                 azimuthDeg: 285, distanceM: 4),
        SoundCue(id: "doorbell", title: "Doorbell", symbol: "bell.fill", group: .traffic,
                 azimuthDeg: 165, directionText: "Behind you"),
    ]

    /// Home, "Today's Feed".
    static let todayCounts: [(group: CueGroup, count: Int)] = [(.urgent, 2), (.speech, 5), (.traffic, 7)]

    static let lastSessionMinutesAgo = 42
    static let lastSessionSounds = 18

    struct Pin: Identifiable, Sendable {
        let id: Int
        let name: String          // Pins tab
        let position: String      // Ecosystem: "Left Pin"
        let battery: Int
        let swatch: (Double, Double, Double)
    }

    static let pins = [
        Pin(id: 1, name: "Pin #1", position: "Left Pin", battery: 88, swatch: (0.10, 0.11, 0.13)),
        Pin(id: 2, name: "Pin #2", position: "Right Pin", battery: 85, swatch: (0.55, 0.50, 0.66)),
        Pin(id: 3, name: "Pin #3", position: "Back Pin", battery: 90, swatch: (0.30, 0.52, 0.85)),
        Pin(id: 4, name: "Pin #4", position: "Front Pin", battery: 92, swatch: (0.93, 0.93, 0.92)),
    ]

    /// Setup step 1, "Devices found nearby".
    static let pinsFoundNearby = ["Pin 1", "Pin 2"]
}
