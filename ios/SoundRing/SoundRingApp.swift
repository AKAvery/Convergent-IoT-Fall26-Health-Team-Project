import Cloud
import SwiftUI

@main
struct SoundRingApp: App {
    init() {
        // No-op (the app runs offline) until GoogleService-Info.plist is added to ios/SoundRing/.
        CloudStore.configure()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
