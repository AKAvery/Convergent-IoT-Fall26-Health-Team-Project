import SwiftUI

/// design-refs/Home.png.
struct HomeView: View {
    @Binding var tab: MainTab
    @State private var profileTab: ProfileTab?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: Theme.Space.l) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Daily commute").font(.title3.weight(.semibold))
                        Text("Ready to go live").foregroundStyle(Theme.secondaryText)
                    }
                    PrimaryButton(title: "Start live view") { tab = .live }
                }
                .padding(.vertical, Theme.Space.s)
            }
            .listRowBackground(Theme.surface)

            Section("Sounds detected") {
                HStack(alignment: .top) {
                    ForEach(DemoData.todayCounts, id: \.group) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(item.count)")
                                .font(.title.weight(.semibold))
                                .monospacedDigit()
                            HStack(spacing: 6) {
                                Circle().fill(item.group.color).frame(width: 8, height: 8)
                                Text(item.group.title)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.secondaryText)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(item.count) \(item.group.title.lowercased())")
                    }
                }
                .padding(.vertical, Theme.Space.xs)
            }
            .listRowBackground(Theme.surface)

            Section {
                row("Pins", detail: "Connection and battery for each pin") { tab = .pins }
                row("Settings", detail: "Sensitivity, sound types, name alerts") { tab = .settings }
            }

            Section("Last session") {
                row("Live session, \(DemoData.lastSessionMinutesAgo) min ago",
                    detail: "\(DemoData.lastSessionSounds) sounds") { profileTab = .feed }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Today")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { AvatarButton { profileTab = .feed } }
        }
        .navigationDestination(item: $profileTab) { ProfileView(initialTab: $0) }
    }

    /// A tappable row with a chevron that switches tab or opens a screen.
    private func row(_ title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(Theme.surface)
    }
}
