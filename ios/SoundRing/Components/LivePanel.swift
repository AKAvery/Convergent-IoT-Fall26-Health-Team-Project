import SwiftUI

/// Which sounds the Live screen shows.
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

/// The dial with the "N active" count under it. The Profile feed post also shows the filter as a
/// menu here; Live has its own segmented control, so it hides this one.
struct LivePanel: View {
    let cues: [SoundCue]
    @Binding var filter: LiveFilter
    var showDistance = true
    var compact = false
    var showsFilterMenu = true

    var body: some View {
        VStack(spacing: Theme.Space.s) {
            SoundDial(cues: cues, showDistance: showDistance, compact: compact)
            HStack {
                if showsFilterMenu {
                    Picker("Show", selection: $filter) {
                        ForEach(LiveFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .tint(Theme.accent)
                }
                Spacer()
                Text("\(cues.count) active")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(Theme.secondaryText)
            }
        }
    }
}

/// LEFT · FRONT · RIGHT strip with a dot for each sound in front of the wearer.
struct FrontScale: View {
    let cues: [SoundCue]

    var body: some View {
        VStack(spacing: Theme.Space.xs) {
            GeometryReader { geo in
                let w = geo.size.width
                let inset: CGFloat = 6
                let y: CGFloat = 8
                ZStack {
                    Rectangle().fill(Theme.line).frame(width: w - 2 * inset, height: 1).position(x: w / 2, y: y)
                    ForEach(0..<9, id: \.self) { i in
                        Rectangle()
                            .fill(Theme.secondaryText.opacity(i % 4 == 0 ? 1 : 0.4))
                            .frame(width: 1, height: i % 4 == 0 ? 12 : 6)
                            .position(x: inset + (w - 2 * inset) * CGFloat(i) / 8, y: y)
                    }
                    ForEach(cues.filter { abs(CueDirection.signed($0.azimuthDeg)) <= 90 }) { cue in
                        Circle()
                            .fill(cue.group.color)
                            .frame(width: 10, height: 10)
                            .position(x: w / 2 + (w / 2 - inset) * CueDirection.signed(cue.azimuthDeg) / 90, y: y)
                    }
                }
            }
            .frame(height: 16)
            HStack {
                Text("Left")
                Spacer()
                Text("Front")
                Spacer()
                Text("Right")
            }
            .font(.caption2)
            .foregroundStyle(Theme.secondaryText)
        }
        .accessibilityHidden(true)
    }
}
