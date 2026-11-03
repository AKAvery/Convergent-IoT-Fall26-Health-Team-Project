import SwiftUI

/// design-refs/Watch_45mm.png: the sound dial on the wrist.
@main
struct SoundRingWatchApp: App {
    var body: some Scene {
        WindowGroup {
            SoundDial(cues: DemoData.welcomeScene, centerSymbol: "eyeglasses", compact: true)
                .padding(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Theme.background)
                .preferredColorScheme(.dark)
        }
    }
}
