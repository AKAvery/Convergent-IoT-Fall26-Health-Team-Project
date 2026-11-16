import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation
import Models
import OSLog

// Lane 3: Firebase (Spark plan: Anonymous Auth + Firestore only).
//
//   users/{uid}/settings/app      one document, see `CloudSettings`
//   users/{uid}/events/{eventId}  one document per finished sound, see `saveEvent`
//
// Audio never goes here, only labels, direction and levels. Rules: firebase/firestore.rules.

/// What syncs between a user's devices. Mirrors the `SettingKey`s in the app.
public struct CloudSettings: Codable, Sendable, Equatable {
    public var detectionSensitivity: Double
    public var alertSensitivity: Double
    public var wristbandHaptics: Bool
    public var showDistance: Bool
    public var nameAlerts: Bool
    public var nameList: String
    /// `SoundLabel` raw values the user muted. nil in documents saved before this existed.
    public var mutedSounds: [String]?

    public init(detectionSensitivity: Double, alertSensitivity: Double, wristbandHaptics: Bool,
                showDistance: Bool, nameAlerts: Bool, nameList: String, mutedSounds: [String]? = nil) {
        self.detectionSensitivity = detectionSensitivity
        self.alertSensitivity = alertSensitivity
        self.wristbandHaptics = wristbandHaptics
        self.showDistance = showDistance
        self.nameAlerts = nameAlerts
        self.nameList = nameList
        self.mutedSounds = mutedSounds
    }
}

public actor CloudStore {
    public static let shared = CloudStore()
    private static let log = Logger(subsystem: "edu.utexas.convergent.soundring", category: "cloud")

    /// Call once at launch. Does nothing if `GoogleService-Info.plist` isn't in the app, so
    /// everyone can build and run without Firebase access.
    public static func configure() {
        guard FirebaseApp.app() == nil else { return }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            log.notice("GoogleService-Info.plist not found: running without Firebase")
            return
        }
        FirebaseApp.configure()
    }

    public nonisolated var isConfigured: Bool { FirebaseApp.app() != nil }

    /// Anonymous sign-in (one tap, no UI). Reuses the existing user across launches.
    private func uid() async -> String? {
        guard isConfigured else { return nil }
        if let user = Auth.auth().currentUser { return user.uid }
        do {
            return try await Auth.auth().signInAnonymously().user.uid
        } catch {
            Self.log.error("anonymous sign-in failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func userDoc(_ uid: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(uid)
    }

    /// Saves a finished sound. Firestore queues writes while offline and sends them later.
    public func saveEvent(_ e: SoundEvent) async {
        guard let uid = await uid() else { return }
        var doc: [String: Any] = [
            "label": e.label.rawValue,
            "confidence": Double(e.confidence),
            "levelDb": Double(e.levelDb),
            "startedAt": Timestamp(date: e.startedAt),
            "endedAt": Timestamp(date: e.updatedAt),
            "isUrgent": e.isUrgent,
            "categories": e.categories.map(\.rawValue).sorted(),
        ]
        if let az = e.azimuthDeg { doc["azimuthDeg"] = Double(az) }
        do {
            try await userDoc(uid).collection("events").document(e.id.uuidString).setData(doc)
        } catch {
            Self.log.error("saveEvent failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func saveSettings(_ s: CloudSettings) async {
        guard let uid = await uid() else { return }
        do {
            try userDoc(uid).collection("settings").document("app").setData(from: s, merge: true)
        } catch {
            Self.log.error("saveSettings failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// nil if offline with nothing cached, not signed in, or never saved.
    public func loadSettings() async -> CloudSettings? {
        guard let uid = await uid() else { return nil }
        let snap = try? await userDoc(uid).collection("settings").document("app").getDocument()
        return try? snap?.data(as: CloudSettings.self)
    }
}
