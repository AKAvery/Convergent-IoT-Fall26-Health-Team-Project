import SwiftUI

enum ProfileTab: String, CaseIterable, Identifiable, Hashable {
    case feed = "Feed", edit = "Edit", ecosystem = "Ecosystem"
    var id: Self { self }

    var symbol: String {
        switch self {
        case .feed: "bolt.circle.fill"
        case .edit: "square.and.pencil"
        case .ecosystem: "point.3.connected.trianglepath.dotted"
        }
    }
}

/// design-refs/Profile_Feed, Profile_Edit, Profile_Ecosystem. Opened from the avatar on Home and
/// Pins, and from "Last session" on Home.
struct ProfileView: View {
    let initialTab: ProfileTab
    @State private var tab: ProfileTab?

    var body: some View {
        let current = tab ?? initialTab
        ScrollView {
            VStack(spacing: 18) {
                header
                HStack(spacing: 10) {
                    ForEach(ProfileTab.allCases) { t in
                        Button { tab = t } label: {
                            Label(t.rawValue, systemImage: t.symbol)
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .background(Capsule().fill(t == current ? Theme.accent : .clear))
                                .overlay(Capsule().stroke(t == current ? .clear : Theme.secondaryText.opacity(0.6)))
                                .foregroundStyle(t == current ? Theme.onAccent : Theme.secondaryText)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 24)

                switch current {
                case .feed: ProfileFeed()
                case .edit: ProfileEdit()
                case .ecosystem: ProfileEcosystem()
                }
            }
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .ignoresSafeArea(edges: .top)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tab = .edit } label: {
                    Image(systemName: "square.and.pencil").font(.title3.weight(.semibold))
                }
                .tint(.white)
                .accessibilityLabel("Edit profile")
            }
        }
        .tint(.white)
    }

    private var header: some View {
        VStack(spacing: 14) {
            ZStack(alignment: .top) {
                Theme.accent.frame(height: 150)
                ZStack(alignment: .bottomTrailing) {
                    Image("ProfileAvatar")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 156, height: 156)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Theme.accent, lineWidth: 4))
                        .accessibilityLabel("Profile photo")
                    Image(systemName: "camera.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Theme.accent))
                        .overlay(Circle().stroke(Theme.background, lineWidth: 3))
                        .offset(x: -4, y: -4)
                        .accessibilityLabel("Change photo")
                }
                .padding(.top, 72)
            }
            Text("User Profile").font(.title.bold())
        }
    }
}

// MARK: - Feed

struct ProfileFeed: View {
    @AppStorage(SettingKey.showDistance) private var showDistance = true
    @State private var filter: LiveFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "figure.stand")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Theme.accentDim))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Username").font(.headline)
                    Text("3h ago").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.leading, 10)
            LivePanel(cues: DemoData.liveScene.filter(filter.includes), filter: $filter,
                      showDistance: showDistance, compact: true)
                .frame(height: 240)
            HStack(spacing: 10) {
                pill("person.2.wave.2.fill", "Feedback")
                pill("questionmark.circle.fill", "FAQ")
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
        .padding(.horizontal, 24)
    }

    private func pill(_ symbol: String, _ title: String) -> some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.accentDim))
            .foregroundStyle(Theme.text)
    }
}

// MARK: - Edit

struct ProfileEdit: View {
    @AppStorage(SettingKey.profileName) private var name = "User"
    @AppStorage(SettingKey.profileBio) private var bio = "Always aware of my surroundings..."
    @AppStorage(SettingKey.profileTheme) private var theme = "Midnight"
    private let bioLimit = 50
    private let themes: [(String, Color)] = [("Midnight", Theme.surface), ("Forest", Theme.ambient),
                                             ("Aurora", Theme.speech), ("Dusk", Theme.urgent)]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field("Name") { TextField("Name", text: $name) }
            field("Bio") {
                HStack(alignment: .bottom) {
                    TextField("Bio", text: $bio)
                        .onChange(of: bio) { _, new in if new.count > bioLimit { bio = String(new.prefix(bioLimit)) } }
                    Text("\(bio.count)/\(bioLimit)").font(.caption).foregroundStyle(Theme.secondaryText)
                }
            }

            Text("Profile Theme").font(.headline).padding(.top, 18)
            Text("Choose a look that fits you").font(.subheadline).foregroundStyle(Theme.secondaryText)
            HStack(spacing: 12) {
                ForEach(themes, id: \.0) { title, color in
                    Button { theme = title } label: {
                        VStack(spacing: 8) {
                            Circle()
                                .fill(color)
                                .overlay(Circle().stroke(theme == title ? Theme.accent : .clear, lineWidth: 2.5))
                                .frame(width: 68, height: 68)
                            Text(title).font(.caption)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(theme == title ? .isSelected : [])
                }
            }
            .padding(.top, 6)
        }
        .padding(.horizontal, 24)
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(Theme.secondaryText)
            content().tint(Theme.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.surface))
    }
}

// MARK: - Ecosystem

struct ProfileEcosystem: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Ecosystem").font(.title3.bold())
                Text("Your Halo ecosystem").font(.subheadline).foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 24)
            EcosystemDiagram()
                .frame(height: 130)
                .padding(.horizontal, 12)
                .background(RoundedRectangle(cornerRadius: 20).fill(Theme.surface))
                .padding(.horizontal, 24)
            WearerPins()
                .padding(.horizontal, 12)
        }
    }
}

/// Phone in the middle, linked to glasses, wristband, home hub and door sensor.
private struct EcosystemDiagram: View {
    private struct Node {
        let symbol: String, title: String, at: CGPoint, online: Bool
    }
    private let nodes = [
        Node(symbol: "eyeglasses", title: "Glasses", at: CGPoint(x: 0.17, y: 0.28), online: true),
        Node(symbol: "applewatch", title: "Wristband", at: CGPoint(x: 0.83, y: 0.28), online: true),
        Node(symbol: "lock.rectangle", title: "Home hub", at: CGPoint(x: 0.17, y: 0.72), online: true),
        Node(symbol: "bell", title: "Door sensor", at: CGPoint(x: 0.83, y: 0.72), online: false),
    ]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let c = CGPoint(x: w / 2, y: h * 0.45)
            ZStack {
                ForEach(nodes.indices, id: \.self) { i in
                    let n = nodes[i]
                    Path { p in
                        p.move(to: c)
                        p.addLine(to: CGPoint(x: n.at.x * w, y: n.at.y * h - 8))
                    }
                    .stroke(Theme.accent.opacity(0.5),
                            style: StrokeStyle(lineWidth: 1, dash: n.online ? [] : [4, 4]))
                }
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(Theme.accentDim))
                    .overlay(Circle().stroke(Theme.accent, lineWidth: 1.5))
                    .shadow(color: Theme.accent.opacity(0.6), radius: 12)
                    .position(c)
                ForEach(nodes.indices, id: \.self) { i in
                    let n = nodes[i]
                    VStack(spacing: 4) {
                        Image(systemName: n.symbol)
                            .font(.subheadline)
                            .foregroundStyle(n.online ? Theme.accent : Theme.secondaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.background))
                            .overlay(Circle().stroke(n.online ? Theme.accent : Theme.secondaryText, lineWidth: 1))
                            .overlay(alignment: .topTrailing) {
                                Circle().fill(n.online ? Theme.ambient : Theme.traffic).frame(width: 7, height: 7)
                            }
                        Text(n.title).font(.caption2).foregroundStyle(Theme.secondaryText)
                    }
                    .position(x: n.at.x * w, y: n.at.y * h)
                }
            }
        }
    }
}

/// The wearer photo from the design with the four pins' cards (battery from DemoData) drawn over
/// the cards baked into the artwork, at the same spots.
private struct WearerPins: View {
    private let cardCenters = [CGPoint(x: 0.267, y: 0.174), CGPoint(x: 0.733, y: 0.174),   // Left, Right
                               CGPoint(x: 0.267, y: 0.753), CGPoint(x: 0.733, y: 0.817)]   // Back, Front

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            ZStack {
                Image("EcosystemWearer")
                    .resizable()
                    .frame(width: w, height: h)
                    .accessibilityHidden(true)
                ForEach(DemoData.pins.indices, id: \.self) { i in
                    PinCard(pin: DemoData.pins[i])
                        .frame(width: w * 0.245, height: h * 0.27)
                        .position(x: cardCenters[i].x * w, y: cardCenters[i].y * h)
                }
            }
        }
        .aspectRatio(393.0 / 215.0, contentMode: .fit)
    }
}

private struct PinCard: View {
    let pin: DemoData.Pin

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(red: pin.swatch.0, green: pin.swatch.1, blue: pin.swatch.2))
                .overlay(Circle().stroke(Theme.accent.opacity(0.6), lineWidth: 1))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(pin.position)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                HStack(spacing: 3) {
                    Image(systemName: "battery.75").foregroundStyle(Theme.ambient)
                    Text("\(pin.battery)%")
                }
                .font(.system(size: 9))
                Text("Active").font(.system(size: 9)).foregroundStyle(Theme.ambient)
            }
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.background))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.accent.opacity(0.35)))
    }
}
