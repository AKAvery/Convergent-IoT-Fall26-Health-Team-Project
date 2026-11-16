import Cloud
import Foundation
import Models

/// UserDefaults keys for everything the screens remember (used with @AppStorage).
enum SettingKey {
    static let hasOnboarded = "hasOnboarded"
    static let detectionSensitivity = "detectionSensitivity"   // 0...1
    static let alertSensitivity = "alertSensitivity"           // 0...1
    static let wristbandHaptics = "wristbandHaptics"
    static let showDistance = "showDistance"
    static let profileName = "profileName"
    static let profileBio = "profileBio"
    static let profileTheme = "profileTheme"
    static let nameAlerts = "nameAlerts"       // Bool, default on
    static let nameList = "nameList"           // "Avery, Ave": names that trigger a name alert
    static let demoRecording = "demoRecording" // WAV in Documents to replay instead of the pins (demos)
    static let logTranscripts = "logTranscripts" // developer: log name-alert transcripts (off)

    static let mutedSounds = "mutedSounds"     // "siren,dog": SoundLabel raw values hidden from Live

    /// "Sounds to detect" toggle for one group.
    static func detect(_ group: CueGroup) -> String { "detect.\(group.rawValue)" }
}

/// The muted-sounds setting as a set of labels (stored as a comma-separated string).
enum MutedSounds {
    static func parse(_ s: String) -> Set<SoundLabel> {
        Set(s.split(separator: ",").compactMap { SoundLabel(rawValue: String($0)) })
    }
    static func serialize(_ labels: Set<SoundLabel>) -> String {
        labels.map(\.rawValue).sorted().joined(separator: ",")
    }
}

/// Keeps the settings in step with Firestore (users/{uid}/settings/app). UserDefaults stays the
/// source the screens read, so the app works offline and before sign-in.
@MainActor
enum SettingsSync {
    private static var lastSynced: CloudSettings?

    static func current() -> CloudSettings {
        let d = UserDefaults.standard
        return CloudSettings(
            detectionSensitivity: d.object(forKey: SettingKey.detectionSensitivity) as? Double ?? 0.45,
            alertSensitivity: d.object(forKey: SettingKey.alertSensitivity) as? Double ?? 0.75,
            wristbandHaptics: d.object(forKey: SettingKey.wristbandHaptics) as? Bool ?? true,
            showDistance: d.object(forKey: SettingKey.showDistance) as? Bool ?? true,
            nameAlerts: d.object(forKey: SettingKey.nameAlerts) as? Bool ?? true,
            nameList: d.string(forKey: SettingKey.nameList) ?? "",
            mutedSounds: MutedSounds.parse(d.string(forKey: SettingKey.mutedSounds) ?? "")
                .map(\.rawValue).sorted())
    }

    /// Saves to Firestore if anything changed since the last save or load.
    static func push() {
        let now = current()
        guard now != lastSynced, CloudStore.shared.isConfigured else { return }
        lastSynced = now
        Task { await CloudStore.shared.saveSettings(now) }
    }

    /// At launch: the saved cloud settings replace the local ones. Does nothing if there are none.
    static func pull() async {
        guard let s = await CloudStore.shared.loadSettings() else { return }
        let d = UserDefaults.standard
        d.set(s.detectionSensitivity, forKey: SettingKey.detectionSensitivity)
        d.set(s.alertSensitivity, forKey: SettingKey.alertSensitivity)
        d.set(s.wristbandHaptics, forKey: SettingKey.wristbandHaptics)
        d.set(s.showDistance, forKey: SettingKey.showDistance)
        d.set(s.nameAlerts, forKey: SettingKey.nameAlerts)
        d.set(s.nameList, forKey: SettingKey.nameList)
        if let muted = s.mutedSounds {
            d.set(MutedSounds.serialize(Set(muted.compactMap(SoundLabel.init(rawValue:)))),
                  forKey: SettingKey.mutedSounds)
        }
        lastSynced = current()
    }
}

enum SensitivityLabel {
    static func text(_ v: Double) -> String { v < 0.34 ? "Low" : v < 0.67 ? "Medium" : "High" }
}
