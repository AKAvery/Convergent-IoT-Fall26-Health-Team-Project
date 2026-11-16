import SwiftUI

enum MainTab: String, CaseIterable, Identifiable {
    case home = "Home", live = "Live", pins = "Pins", settings = "Settings"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .live: "dot.radiowaves.left.and.right"
        case .pins: "circle.grid.2x2.fill"
        case .settings: "gearshape"
        }
    }
}

/// The four tabs with the design's custom tab bar (cyan line above the selected tab).
struct MainTabsView: View {
    @State private var tab: MainTab = .home

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack { HomeView(tab: $tab) }.tag(MainTab.home)
            NavigationStack { LiveView() }.tag(MainTab.live)
            NavigationStack { PinsView() }.tag(MainTab.pins)
            NavigationStack { SettingsView() }.tag(MainTab.settings)
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { MainTabBar(tab: $tab) }
    }
}

struct MainTabBar: View {
    @Binding var tab: MainTab

    var body: some View {
        HStack {
            ForEach(MainTab.allCases) { t in
                Button { tab = t } label: {
                    VStack(spacing: 6) {
                        Capsule()
                            .fill(t == tab ? Theme.accent : .clear)
                            .frame(width: 28, height: 3)
                        Image(systemName: t.symbol).font(.title3)
                        Text(t.rawValue).font(.caption)
                    }
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(t == tab ? Theme.accent : Theme.secondaryText)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(t == tab ? .isSelected : [])
            }
        }
        .padding(.bottom, 6)
        .background(Theme.surface.ignoresSafeArea(edges: .bottom))
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
    }
}
