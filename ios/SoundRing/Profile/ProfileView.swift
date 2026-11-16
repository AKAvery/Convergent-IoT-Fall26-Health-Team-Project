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

/// design-refs/Profile_Feed, Profile_Edit, Profile_Ecosystem. Opened from the profile button on
/// Home and Pins, and from "Last session" on Home.
struct ProfileView: View {
    let initialTab: ProfileTab
    @State private var tab: ProfileTab?
    @AppStorage(SettingKey.profileName) private var name = "User"

    var body: some View {
        let current = tab ?? initialTab
        ScrollView {
            VStack(spacing: Theme.Space.l) {
                header
                Picker("Section", selection: Binding(get: { current }, set: { tab = $0 })) {
                    ForEach(ProfileTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Space.margin)

                switch current {
                case .feed: ProfileFeed()
                case .edit: ProfileEdit()
                case .ecosystem: ProfileEcosystem()
                }
            }
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { tab = .edit } label: {
                    Image(systemName: "square.and.pencil")
                }
                .accessibilityLabel("Edit profile")
            }
        }
        .tint(Theme.accent)
    }

    private var header: some View {
        VStack(spacing: Theme.Space.m) {
            Image("ProfileAvatar")
                .resizable()
                .scaledToFill()
                .frame(width: 96, height: 96)
                .clipShape(Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.text)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.fill))
                        .overlay(Circle().stroke(Theme.background, lineWidth: 2))
                        .accessibilityHidden(true)
                }
                .accessibilityLabel("Profile photo")
            Text(name)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
        }
        .padding(.top, Theme.Space.s)
    }
}

// MARK: - Feed

struct ProfileFeed: View {
    @AppStorage(SettingKey.showDistance) private var showDistance = true
    @AppStorage(SettingKey.profileName) private var name = "User"
    @State private var filter: LiveFilter = .all

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.m) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.secondaryText)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).font(.headline)
                    Text("3h ago").font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            LivePanel(cues: DemoData.liveScene.filter(filter.includes), filter: $filter,
                      showDistance: showDistance, compact: true)
            HStack(spacing: Theme.Space.s) {
                // No destinations yet; same as the design, where these are placeholders.
                Button {} label: { Label("Feedback", systemImage: "bubble.left") }
                Button {} label: { Label("FAQ", systemImage: "questionmark.circle") }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, Theme.Space.margin)
    }
}

// MARK: - Edit

struct ProfileEdit: View {
    @AppStorage(SettingKey.profileName) private var name = "User"
    @AppStorage(SettingKey.profileBio) private var bio = "Always aware of my surroundings..."
    @AppStorage(SettingKey.profileTheme) private var theme = "Midnight"
    private let bioLimit = 50

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            VStack(spacing: 0) {
                field("Name") { TextField("Name", text: $name) }
                Rectangle().fill(Theme.line).frame(height: 1).padding(.leading, Theme.Space.m)
                field("Bio") {
                    HStack(alignment: .firstTextBaseline) {
                        TextField("Bio", text: $bio)
                            .onChange(of: bio) { _, new in
                                if new.count > bioLimit { bio = String(new.prefix(bioLimit)) }
                            }
                        Text("\(bio.count)/\(bioLimit)")
                            .font(.footnote)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                            .accessibilityLabel("\(bio.count) of \(bioLimit) characters")
                    }
                }
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(Theme.surface))

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                SectionLabel("Profile theme")
                HStack(spacing: Theme.Space.m) {
                    ForEach(Theme.profileThemes, id: \.name) { option in
                        let selected = theme == option.name
                        Button { theme = option.name } label: {
                            VStack(spacing: Theme.Space.s) {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 44, height: 44)
                                    .padding(4)
                                    .overlay(Circle().stroke(selected ? Theme.text : .clear, lineWidth: 2))
                                Text(option.name)
                                    .font(.caption.weight(selected ? .semibold : .regular))
                                    .foregroundStyle(selected ? Theme.text : Theme.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Space.margin)
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Text(title).font(.footnote).foregroundStyle(Theme.secondaryText)
            content().tint(Theme.accent)
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, Theme.Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Ecosystem

struct ProfileEcosystem: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            SectionLabel("Connected devices")
                .padding(.horizontal, Theme.Space.margin)
            EcosystemDiagram()
                .frame(height: 150)
                .padding(.horizontal, Theme.Space.margin)
            WearerPins()
                .padding(.horizontal, Theme.Space.s)
        }
    }
}

/// Phone in the middle, linked to glasses, wristband, home hub and door sensor. Offline devices
/// get a dashed link and say "Offline".
private struct EcosystemDiagram: View {
    private struct Node {
        let symbol: String, title: String, at: CGPoint, online: Bool
    }
    private let nodes = [
        Node(symbol: "eyeglasses", title: "Glasses", at: CGPoint(x: 0.15, y: 0.25), online: true),
        Node(symbol: "applewatch", title: "Wristband", at: CGPoint(x: 0.85, y: 0.25), online: true),
        Node(symbol: "lock.rectangle", title: "Home hub", at: CGPoint(x: 0.15, y: 0.72), online: true),
        Node(symbol: "bell", title: "Door sensor", at: CGPoint(x: 0.85, y: 0.72), online: false),
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
                        p.addLine(to: CGPoint(x: n.at.x * w, y: n.at.y * h - 10))
                    }
                    .stroke(n.online ? Theme.secondaryText.opacity(0.6) : Theme.line,
                            style: StrokeStyle(lineWidth: 1, dash: n.online ? [] : [4, 4]))
                }
                Image(systemName: "iphone")
                    .font(.title2)
                    .foregroundStyle(Theme.text)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(Theme.surface))
                    .overlay(Circle().stroke(Theme.line))
                    .position(c)
                ForEach(nodes.indices, id: \.self) { i in
                    let n = nodes[i]
                    VStack(spacing: 2) {
                        Image(systemName: n.symbol)
                            .font(.subheadline)
                            .foregroundStyle(n.online ? Theme.text : Theme.secondaryText)
                            .frame(width: 34, height: 34)
                            .background(Circle().fill(Theme.surface))
                            .overlay(Circle().stroke(Theme.line))
                        Text(n.title).font(.caption2)
                        if !n.online {
                            Text("Offline").font(.caption2).foregroundStyle(Theme.secondaryText)
                        }
                    }
                    .position(x: n.at.x * w, y: n.at.y * h + (n.online ? 0 : 6))
                }
            }
        }
        .dynamicTypeSize(...DynamicTypeSize.xLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
    }

    private var summary: String {
        let online = nodes.filter { $0.online }.map { $0.title }.joined(separator: ", ")
        let offline = nodes.filter { !$0.online }.map { $0.title }.joined(separator: ", ")
        return "iPhone connected to \(online). Offline: \(offline)"
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
                .overlay(Circle().stroke(Theme.line, lineWidth: 1))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 1) {
                Text(pin.position)
                    .font(.caption.weight(.semibold))
                Label("\(pin.battery)%", systemImage: "battery.75")
                    .labelStyle(.titleAndIcon)
                    .font(.caption2)
                Text("Active").font(.caption2).foregroundStyle(Theme.secondaryText)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.chip).fill(Theme.surface))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip).stroke(Theme.line))
        .dynamicTypeSize(...DynamicTypeSize.large)
        .accessibilityElement(children: .combine)
    }
}
