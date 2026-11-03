import SwiftUI

struct HomeView: View {
    @Binding var tab: MainTab
    @AppStorage(SettingKey.profileName) private var name = "User"
    @State private var profileTab: ProfileTab?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Welcome back").foregroundStyle(Theme.secondaryText)
                        Text(name).font(.largeTitle.bold())
                    }
                    Spacer()
                    AvatarButton { profileTab = .feed }
                }

                commuteCard

                section("Today\u{2019}s Feed") {
                    HStack(spacing: 10) {
                        ForEach(DemoData.todayCounts, id: \.group) { item in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 6) {
                                    Circle().fill(item.group.color).frame(width: 8, height: 8)
                                    Text(item.group.title).font(.subheadline).foregroundStyle(Theme.secondaryText)
                                }
                                Text("\(item.count)").font(.title.bold())
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .card(radius: 16)
                        }
                    }
                }

                section("Widgets") {
                    HStack(spacing: 12) {
                        widget(symbol: "circle.grid.2x2.fill", title: "Devices", subtitle: "Manage ecosystem") { tab = .pins }
                        widget(symbol: "gearshape", title: "Settings", subtitle: "Adjust your preferences") { tab = .settings }
                    }
                }

                section("Last session") {
                    Button { profileTab = .feed } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "dot.radiowaves.up.forward")
                                .font(.title3)
                                .foregroundStyle(Theme.accent)
                                .frame(width: 40, height: 40)
                                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.accentDim))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Live Session \(DemoData.lastSessionMinutesAgo) minutes ago").font(.headline)
                                Text("\(DemoData.lastSessionSounds) sounds detected")
                                    .font(.subheadline).foregroundStyle(Theme.secondaryText)
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.secondaryText)
                        }
                        .padding(14)
                        .card(radius: 16)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .navigationDestination(item: $profileTab) { ProfileView(initialTab: $0) }
    }

    private var commuteCard: some View {
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                ZStack {
                    ForEach(0..<3, id: \.self) { i in
                        Circle().stroke(Theme.accent.opacity(0.25 + 0.2 * Double(i)), lineWidth: 1.5)
                            .frame(width: 64 - CGFloat(i) * 16, height: 64 - CGFloat(i) * 16)
                    }
                    Circle().fill(Theme.accentDim).frame(width: 30, height: 30)
                }
                .frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your Daily Commute").font(.title3.bold())
                    Text("Ready to go live").foregroundStyle(Theme.secondaryText)
                }
                Spacer()
            }
            PrimaryButton(title: "Connect & start live view") { tab = .live }
        }
        .padding(18)
        .card(radius: 22, stroke: Theme.accent.opacity(0.7))
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).foregroundStyle(Theme.secondaryText)
            content()
        }
    }

    private func widget(symbol: String, title: String, subtitle: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36, height: 36)
                    .background(RoundedRectangle(cornerRadius: 9).fill(Theme.accentDim))
                    .padding(.bottom, 8)
                Text(title).font(.headline)
                Text(subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .card(radius: 16)
        }
        .buttonStyle(.plain)
    }
}
