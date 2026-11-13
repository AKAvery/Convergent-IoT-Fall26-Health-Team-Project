import SwiftUI

/// Settings section: alert when someone says the wearer's name (Apple's on-device speech-to-text on
/// the pins' audio, iOS 26+). Names are whole words: "Avery" never fires on "every" or "bravery".
struct NameAlertsSection: View {
    @AppStorage(SettingKey.nameAlerts) private var on = true
    @AppStorage(SettingKey.nameList) private var names = ""
    private let session = LiveSession.shared

    var body: some View {
        Section {
            Toggle(isOn: $on) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name alerts")
                    Text("Alert when someone says your name")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text("Your name and nicknames")
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                TextField("e.g. Avery, Ave", text: $names)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Your name and nicknames, separated by commas")
            }
            .disabled(!on)
        } footer: {
            Text(session.nameStatus ?? "Separate names with commas. Matching happens on this iPhone only.")
        }
        .listRowBackground(Theme.surface)
        .onChange(of: on) { session.updateNameAlerts() }
        .onChange(of: names) { session.updateNameAlerts() }
    }
}
