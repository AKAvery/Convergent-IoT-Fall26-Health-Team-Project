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

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Settings").font(.largeTitle.bold()).padding(.bottom, 10)

                slider("Detection sensitivity", value: $detection)
                    .padding(16)
                    .card()

                Text("Sounds to detect").foregroundStyle(Theme.secondaryText).padding(.top, 8)
                VStack(spacing: 0) {
                    groupToggle(.urgent, $detectUrgent)
                    Divider().overlay(Theme.line)
                    groupToggle(.traffic, $detectTraffic)
                    Divider().overlay(Theme.line)
                    groupToggle(.speech, $detectSpeech)
                    Divider().overlay(Theme.line)
                    groupToggle(.ambient, $detectAmbient)
                }
                .card()

                Text("Alerts & Feedback").foregroundStyle(Theme.secondaryText).padding(.top, 8)
                VStack(spacing: 0) {
                    slider("Alert sensitivity", value: $alert).padding(16)
                    Divider().overlay(Theme.line)
                    iconToggle(symbol: "iphone.radiowaves.left.and.right", title: "Wristband haptics",
                               subtitle: "Pulse pattern by sound type", isOn: $haptics)
                    Divider().overlay(Theme.line)
                    iconToggle(symbol: "figure.stand", title: "Show distance labels",
                               subtitle: "Meters next to each recorded sound", isOn: $showDistance)
                }
                .card()
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
        .background(Theme.background)
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
    }

    private func slider(_ title: String, value: Binding<Double>) -> some View {
        VStack(spacing: 8) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                Text(SensitivityLabel.text(value.wrappedValue)).font(.headline).foregroundStyle(Theme.accent)
            }
            Slider(value: value, in: 0...1)
                .accessibilityLabel(title)
        }
    }

    private func groupToggle(_ group: CueGroup, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 20) {
                Circle().fill(group.color).frame(width: 26, height: 26)
                Text(group.title).font(.headline)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func iconToggle(symbol: String, title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
}
