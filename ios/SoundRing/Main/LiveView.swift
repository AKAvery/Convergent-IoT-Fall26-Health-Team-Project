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
            VStack(alignment: .leading, spacing: Theme.Space.l) {
                Text(session.summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                // Above everything else so an urgent sound is seen without scrolling.
                if let main, main.isUrgent {
                    UrgentBanner(cue: main)
                        .transition(.opacity)
                }
                FrontScale(cues: visible)
                LivePanel(cues: visible, filter: $filter, showDistance: showDistance, showsFilterMenu: false)
                    .frame(maxWidth: 300)
                    .frame(maxWidth: .infinity)
                Picker("Show", selection: $filter) {
                    ForEach(LiveFilter.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                if let main {
                    Divider().overlay(Theme.line)
                    LiveSoundCard(cue: main, showDistance: showDistance)
                }
            }
            .padding(.horizontal, Theme.Space.margin)
            .padding(.bottom, Theme.Space.xl)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Live")
        .task { await model.listen(to: source) }
    }
}

/// Full-width filled bar at the top of Live while the most important sound is urgent.
struct UrgentBanner: View {
    let cue: SoundCue

    var body: some View {
        Label("Urgent: \(cue.title), \(cue.direction.lowercased())", systemImage: "exclamationmark.triangle.fill")
            .font(.headline)
            .foregroundStyle(Theme.onAccent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.Space.m)
            .padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: Theme.Radius.control).fill(cue.group.color))
            .accessibilityAddTraits(.isHeader)
    }
}

/// The most important sound right now: what it is, how far and which way.
struct LiveSoundCard: View {
    let cue: SoundCue
    let showDistance: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Image(systemName: cue.symbol)
                    .font(.title2)
                    .foregroundStyle(cue.group.color)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cue.title).font(.title2.weight(.semibold))
                    Text(cue.longDetail(showDistance: showDistance))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Waveform(color: cue.group.color)
                .frame(height: 40)
        }
        .accessibilityElement(children: .combine)
    }
}
