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
                    .foregroundStyle(Theme.text)
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
