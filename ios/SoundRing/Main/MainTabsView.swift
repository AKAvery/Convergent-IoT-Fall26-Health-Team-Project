import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home", live = "Live", pins = "Pins", settings = "Settings"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "house"
        case .live: "dot.radiowaves.left.and.right"
        case .pins: "circle.grid.2x2"
        case .settings: "gearshape"
        }
    }
}

/// The four tabs, on the system tab bar.
struct MainTabsView: View {
    @State private var tab: MainTab

    init(initial: MainTab = .home) {
        _tab = State(initialValue: initial)
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }
                .tabItem { Label(MainTab.home.rawValue, systemImage: MainTab.home.symbol) }
                .tag(MainTab.home)
            NavigationStack { LiveView() }
                .tabItem { Label(MainTab.live.rawValue, systemImage: MainTab.live.symbol) }
                .tag(MainTab.live)
            NavigationStack { PinsView() }
                .tabItem { Label(MainTab.pins.rawValue, systemImage: MainTab.pins.symbol) }
                .tag(MainTab.pins)
            NavigationStack { SettingsView() }
                .tabItem { Label(MainTab.settings.rawValue, systemImage: MainTab.settings.symbol) }
                .tag(MainTab.settings)
        }
        .tint(Theme.accent)
    }
}
