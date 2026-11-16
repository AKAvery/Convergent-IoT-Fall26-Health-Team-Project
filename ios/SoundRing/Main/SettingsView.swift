import Combine
import Models
import SwiftUI

/// design-refs/Settings.png. Every control is saved; "Sounds to detect" and "Show distance
/// labels" already change the Live screen.
struct SettingsView: View {
    @AppStorage(SettingKey.detectionSensitivity) private var detection = 0.45
    @AppStorage(SettingKey.alertSensitivity) private var alert = 0.75
    @AppStorage(SettingKey.wristbandHaptics) private var haptics = true
    @AppStorage(SettingKey.showDistance) private var showDistance = true
    @AppStorage(SettingKey.detect(.urgent)) private var detectUrgent = true
    @AppStorage(SettingKey.detect(.traffic)) private var detectTraffic = true
    @AppStorage(SettingKey.detect(.speech)) private var detectSpeech = true
    @AppStorage(SettingKey.detect(.ambient)) private var detectAmbient = true
    @AppStorage(SettingKey.mutedSounds) private var mutedSounds = ""

    var body: some View {
        Form {
            Section {
                slider("Detection sensitivity", value: $detection)
            }
            .listRowBackground(Theme.surface)

            Section("Sounds to detect") {
                groupToggle(.urgent, $detectUrgent)
                groupToggle(.traffic, $detectTraffic)
                groupToggle(.speech, $detectSpeech)
                groupToggle(.ambient, $detectAmbient)
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach(SoundLabel.allCases, id: \.self) { soundToggle($0) }
            } header: {
                Text("Filter sounds")
            } footer: {
                Text("Turn a sound off to hide it from the Live view. Muting safety sounds (siren, alarm, glass breaking, car horn) means you won't see them.")
            }
            .listRowBackground(Theme.surface)

            NameAlertsSection()

            Section("Alerts") {
                slider("Alert sensitivity", value: $alert)
                toggle("Wristband haptics", detail: "Pulse pattern by sound type", isOn: $haptics)
                toggle("Show distance labels", detail: "Show how far away each sound is, in meters",
                       isOn: $showDistance)
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .tint(Theme.accent)
        .navigationTitle("Settings")
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .seconds(1), scheduler: DispatchQueue.main)) { _ in SettingsSync.push() }
        .onDisappear { SettingsSync.push() }
    }

    /// On = this sound shows up; off = it's muted.
    private func soundToggle(_ label: SoundLabel) -> some View {
        let look = SoundCue.look[label] ?? (title: "Sound", symbol: "waveform")
        let isOn = Binding<Bool>(
            get: { !MutedSounds.parse(mutedSounds).contains(label) },
            set: { on in
                var muted = MutedSounds.parse(mutedSounds)
                if on { muted.remove(label) } else { muted.insert(label) }
                mutedSounds = MutedSounds.serialize(muted)
            })
        return Toggle(isOn: isOn) {
            Label(look.title, systemImage: look.symbol)
        }
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack {
                Text(title)
                Spacer()
                Text(SensitivityLabel.text(value.wrappedValue)).foregroundStyle(Theme.secondaryText)
            }
            Slider(value: value, in: 0...1)
                .accessibilityLabel(title)
                .accessibilityValue(SensitivityLabel.text(value.wrappedValue))
        }
        .padding(.vertical, Theme.Space.xs)
    }

    /// One sound group: its colour (the same dot used on Home and the dial), name and what's in it.
    private func groupToggle(_ group: CueGroup, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(alignment: .top, spacing: Theme.Space.m) {
                Circle()
                    .fill(group.color)
                    .frame(width: 10, height: 10)
                    .padding(.top, 6)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(group.title)
                    Text(examples(group)).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }

    private func examples(_ group: CueGroup) -> String {
        switch group {
        case .urgent: "Sirens, alarms, car horns, glass breaking, a baby crying"
        case .traffic: "Bike bells, doorbells"
        case .speech: "People talking"
        case .ambient: "Dogs, cats, knocks, footsteps, appliances"
        }
    }

    private func toggle(_ title: String, detail: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.footnote).foregroundStyle(Theme.secondaryText)
            }
        }
    }
}
