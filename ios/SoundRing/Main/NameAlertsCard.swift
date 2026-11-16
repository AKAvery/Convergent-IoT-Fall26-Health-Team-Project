import SwiftUI

/// Settings card: alert when someone says the wearer's name (Apple's on-device speech-to-text on
/// the pins' audio, iOS 26+). Names are whole words: "Avery" never fires on "every" or "bravery".
struct NameAlertsCard: View {
    @AppStorage(SettingKey.nameAlerts) private var on = true
    @AppStorage(SettingKey.nameList) private var names = ""
    private let session = LiveSession.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: $on) {
                HStack(spacing: 14) {
                    Image(systemName: "person.wave.2.fill")
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                        .frame(width: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Name alerts").font(.headline)
                        Text("Alert when someone says your name").font(.footnote).foregroundStyle(Theme.secondaryText)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 6) {
                Text("Your name and nicknames").font(.subheadline).foregroundStyle(Theme.secondaryText)
                TextField("e.g. Avery, Ave", text: $names)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Your name and nicknames, separated by commas")
                if let status = session.nameStatus {
                    Text(status).font(.footnote).foregroundStyle(Theme.secondaryText)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            .disabled(!on)
            .opacity(on ? 1 : 0.5)
        }
        .card()
        .onChange(of: on) { session.updateNameAlerts() }
        .onChange(of: names) { session.updateNameAlerts() }
    }
}
