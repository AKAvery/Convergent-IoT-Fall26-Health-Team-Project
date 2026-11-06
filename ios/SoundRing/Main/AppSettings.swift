import Foundation

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

    /// "Sounds to detect" toggle for one group.
    static func detect(_ group: CueGroup) -> String { "detect.\(group.rawValue)" }
}

enum SensitivityLabel {
    static func text(_ v: Double) -> String { v < 0.34 ? "Low" : v < 0.67 ? "Medium" : "High" }
}
