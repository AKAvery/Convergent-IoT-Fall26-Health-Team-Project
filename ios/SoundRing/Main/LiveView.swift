import SwiftUI

@MainActor @Observable
final class LiveModel {
    var cues: [SoundCue] = []

    func listen(to source: any CueSource) async {
        for await snapshot in source.cues { cues = snapshot }
    }
}

struct LiveView: View {
    var source: any CueSource = LiveCueSource()
    private let session = LiveSession.shared
    @State private var model = LiveModel()
    @State private var filter: LiveFilter = .all
    @AppStorage(SettingKey.showDistance) private var showDistance = true
    @AppStorage(SettingKey.detect(.urgent)) private var detectUrgent = true
    @AppStorage(SettingKey.detect(.traffic)) private var detectTraffic = true
    @AppStorage(SettingKey.detect(.speech)) private var detectSpeech = true
    @AppStorage(SettingKey.detect(.ambient)) private var detectAmbient = true

    /// Settings "Sounds to detect" first, then this screen's filter.
    private var visible: [SoundCue] {
        model.cues.filter { cue in
            let enabled = switch cue.group {
            case .urgent: detectUrgent
            case .traffic: detectTraffic
            case .speech: detectSpeech
            case .ambient: detectAmbient
            }
            return enabled && filter.includes(cue)
        }
    }

    /// The card shows the most important sound: urgent first, then the nearest.
    private var main: SoundCue? {
        visible.min { a, b in
            if a.isUrgent != b.isUrgent { return a.isUrgent }
            return (a.distanceM ?? .infinity) < (b.distanceM ?? .infinity)
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text("Live view").font(.largeTitle.bold())
                    Spacer()
                    Image(systemName: "location.viewfinder")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)
                }
                Text(session.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FrontScale(cues: visible)
                LivePanel(cues: visible, filter: $filter, showDistance: showDistance)
                    .frame(height: 330)
                HStack(spacing: 10) {
                    ForEach(LiveFilter.allCases) { f in
                        Button(f.rawValue) { filter = f }
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16).padding(.vertical, 10)
                            .background(Capsule().fill(filter == f ? Theme.accent : .clear))
                            .overlay(Capsule().stroke(filter == f ? .clear : Theme.line))
                            .foregroundStyle(filter == f ? Theme.background : Theme.secondaryText)
                    }
                }
                .buttonStyle(.plain)
                if let main {
                    LiveSoundCard(cue: main, showDistance: showDistance)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .task { await model.listen(to: source) }
    }
}

struct LiveSoundCard: View {
    let cue: SoundCue
    let showDistance: Bool

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 14) {
                Image(systemName: cue.symbol)
                    .font(.title3)
                    .foregroundStyle(cue.group.color)
                    .frame(width: 46, height: 46)
                    .background(RoundedRectangle(cornerRadius: 12).fill(cue.group.color.opacity(0.22)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.title).font(.title3.bold())
                    Text(cue.longDetail(showDistance: showDistance))
                        .foregroundStyle(Theme.secondaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                Spacer()
                if cue.isUrgent {
                    Text("High priority")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .overlay(Capsule().stroke(cue.group.color))
                        .foregroundStyle(cue.group.color)
                }
            }
            Waveform(color: cue.group.color)
                .frame(height: 64)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.background))
        }
        .padding(16)
        .card(radius: 20, stroke: Theme.accent.opacity(0.7))
        .accessibilityElement(children: .combine)
    }
}
