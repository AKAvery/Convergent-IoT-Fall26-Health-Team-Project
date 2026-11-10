import SwiftUI
#if os(watchOS)
import WatchKit
#endif

/// What the Watch shows. Demo scenes for now; when the iPhone starts sending cues (WatchConnectivity),
/// set `cues` from there and drop `playDemo()`.
@MainActor @Observable
final class WatchFeed {
    private(set) var cues: [SoundCue] = []

    /// The one sound the Watch talks about: urgent first, then the nearest (same rule as the
    /// iPhone Live card).
    var primary: SoundCue? { Self.ranked(cues).first }

    /// Most important first, for the list page.
    var ranked: [SoundCue] { Self.ranked(cues) }

    func update(_ new: [SoundCue]) {
        let oldPrimary = primary?.id
        cues = new
        // Tap the wrist when a new sound takes the top spot; a stronger tap if it is urgent.
        if let p = primary, p.id != oldPrimary { Self.tap(urgent: p.isUrgent) }
    }

    /// Cycles through a few scenes so the demo looks alive.
    func playDemo() async {
        var i = 0
        while !Task.isCancelled {
            update(Self.demoScenes[i % Self.demoScenes.count])
            i += 1
            try? await Task.sleep(for: .seconds(6))
        }
    }

    static func ranked(_ cues: [SoundCue]) -> [SoundCue] {
        cues.sorted { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return (a.distanceM ?? .infinity) < (b.distanceM ?? .infinity)
        }
    }

    private static func tap(urgent: Bool) {
        #if os(watchOS)
        WKInterfaceDevice.current().play(urgent ? .notification : .click)
        #endif
    }

    static let demoScenes: [[SoundCue]] = [
        DemoData.welcomeScene,
        [DemoData.heyAlex, DemoData.dogBark],
        [],
        [DemoData.bikeBell],
    ]
}
