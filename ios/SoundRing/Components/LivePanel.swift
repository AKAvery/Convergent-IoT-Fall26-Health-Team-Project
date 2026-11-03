import SwiftUI

/// Which sounds the Live screen shows. The same three options as the chips and the menu.
enum LiveFilter: String, CaseIterable, Identifiable {
    case all = "All sounds", urgent = "Urgent only", speech = "Speech"
    var id: Self { self }

    func includes(_ cue: SoundCue) -> Bool {
        switch self {
        case .all: true
        case .urgent: cue.isUrgent
        case .speech: cue.group == .speech
        }
    }
}

/// The grid + dial box with the "All sounds" menu and "N active" pill. Used on Live and in the
/// Profile feed post.
struct LivePanel: View {
    let cues: [SoundCue]
    @Binding var filter: LiveFilter
    var showDistance = true
    var compact = false

    var body: some View {
        ZStack(alignment: .bottom) {
            PerspectiveGrid()
            SoundDial(cues: cues, centerSymbol: "scope", showDistance: showDistance,
                      compact: compact, showBackdrop: false)
                .padding(compact ? 8 : 12)
                .padding(.bottom, compact ? 20 : 28)
            HStack {
                Menu {
                    Picker("Show", selection: $filter) {
                        ForEach(LiveFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Circle().fill(Theme.accent).frame(width: 7, height: 7)
                        Text(filter.rawValue)
                        Image(systemName: "chevron.down").font(.caption2.bold())
                    }
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surfaceRaised))
                }
                Spacer()
                Text("\(cues.count) active")
                    .font((compact ? Font.caption : .subheadline).weight(.semibold))
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(Theme.surfaceRaised))
            }
            .padding(compact ? 8 : 12)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .background(RoundedRectangle(cornerRadius: 22).fill(Theme.background))
    }
}

/// LEFT · FRONT · RIGHT strip with a dot for each sound in front of the wearer.
struct FrontScale: View {
    let cues: [SoundCue]

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let inset: CGFloat = 22
            ZStack {
                Capsule().fill(Theme.surface)
                Capsule().stroke(Theme.line)
                ForEach(0..<17, id: \.self) { i in
                    Rectangle()
                        .fill(Theme.secondaryText.opacity(i % 4 == 0 ? 0.8 : 0.4))
                        .frame(width: 1, height: i % 4 == 0 ? 12 : 7)
                        .position(x: inset + (w - 2 * inset) * CGFloat(i) / 16, y: 16)
                }
                Image(systemName: "arrowtriangle.down.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Theme.accent)
                    .position(x: w / 2, y: 4)
                ForEach(cues.filter { abs(CueDirection.signed($0.azimuthDeg)) <= 90 }) { cue in
                    Circle()
                        .fill(cue.group.color)
                        .frame(width: 11, height: 11)
                        .shadow(color: cue.group.color, radius: 4)
                        .position(x: w / 2 + (w / 2 - inset) * CueDirection.signed(cue.azimuthDeg) / 90, y: 16)
                }
                HStack {
                    Text("LEFT")
                    Spacer()
                    Text("FRONT")
                    Spacer()
                    Text("RIGHT")
                }
                .font(.system(size: 9, weight: .semibold)).tracking(1)
                .foregroundStyle(Theme.secondaryText)
                .padding(.horizontal, 18)
                .position(x: w / 2, y: 36)
            }
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }
}
