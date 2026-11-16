import SwiftUI

/// The wrist version of Halo: glance, see which way to look, put the arm down.
/// Two pages (swipe or turn the Digital Crown): Now (dial + top sound) and Sounds (short list).
/// Settings, pins, history and name alerts stay on the iPhone.
@main
struct SoundRingWatchApp: App {
    @State private var feed = WatchFeed()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                TabView {
                    WatchNowView(feed: feed)
                        .watchPage()
                    WatchListView(feed: feed)
                        .watchPage()
                }
                .watchPagingStyle()
            }
            .preferredColorScheme(.dark)
            .task { await feed.playDemo() }
        }
    }
}

private extension View {
    func watchPage() -> some View {
        #if os(watchOS)
        containerBackground(Theme.background.gradient, for: .tabView)
        #else
        background(Theme.background)
        #endif
    }

    func watchPagingStyle() -> some View {
        #if os(watchOS)
        tabViewStyle(.verticalPage)
        #else
        self
        #endif
    }
}
