import Cloud
import Detection
import Foundation
import Input
import Models
import Names
import OSLog

/// The real pipeline behind the Live and Pins screens: the 4 boxes over BLE (or, in the Simulator,
/// a demo WAV through the same ADPCM path), YAMNet + our head, direction, events. Started the first
/// time a screen needs it and kept running while the app is open.
@MainActor @Observable
final class LiveSession {
    static let shared = LiveSession()

    enum Input: Equatable {
        case boxes                 // real boxes over Bluetooth
        case demoFile              // a recording (Simulator: no CoreBluetooth; or `demoRecording`)
    }

    private(set) var input: Input
    private(set) var events: [SoundEvent] = []
    private(set) var ble = BLESnapshot()
    private(set) var status = DetectionStatus()
    private(set) var error: String?
    private(set) var running = false
    /// "Someone said your name", newest first; each stays `NameAlert.showS`.
    private(set) var nameAlerts: [NameAlert] = []
    /// What name alerts are doing, for Settings (nil = off).
    private(set) var nameStatus: String? {
        didSet { if nameStatus != oldValue { Self.log.info("name alerts: \(self.nameStatus ?? "off", privacy: .public)") } }
    }
    private static let log = Logger(subsystem: "edu.utexas.convergent.soundring", category: "names")

    private var bleSource: BLEBoxSource?
    private let nameFeed = NameFeed()
    private var nameTask: Task<Void, Never>?
    private var nameListener: AnyObject?       // a NameListener (iOS 26+)
    private var file: WavFileBoxSource?
    private var tasks: [Task<Void, Never>] = []

    /// The recording `.demoFile` plays: `demoRecording` (a WAV in the app's Documents folder) if
    /// that setting is set, else the bundled demo_sounds.wav.
    private let demoURL: URL?

    private init() {
        // Demos without pins (e.g. a Mac, where the iOS Simulator's missing speech-to-text exists):
        //   defaults write <app> demoRecording my_take.wav   (16 kHz mono 16-bit, in Documents)
        let custom = UserDefaults.standard.string(forKey: SettingKey.demoRecording).flatMap { name in
            URL.documentsDirectory.appendingPathComponent(name)
        }.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        demoURL = custom ?? Bundle.main.url(forResource: "demo_sounds", withExtension: "wav")
        #if targetEnvironment(simulator)
        input = .demoFile
        #else
        input = custom == nil ? .boxes : .demoFile
        #endif
    }

    /// Firebase history: each sound is saved once, after it stops. Firestore queues it if offline.
    private var saved: Set<UUID> = []
    private func saveFinished(_ snapshot: [SoundEvent]) {
        for e in snapshot where !e.isActive && saved.insert(e.id).inserted {
            Task { await CloudStore.shared.saveEvent(e) }
        }
    }

    func start() {
        guard !running else { return }
        do {
            let classifier = try TFLiteClassifier()
            let rules = try LabelRules.bundled()
            let source: any BoxSource & Sendable
            switch input {
            case .boxes:
                let s = BLEBoxSource(restoreIdentifier: "edu.utexas.convergent.soundring.boxes")
                bleSource = s
                source = s
                tasks.append(Task { [weak self] in
                    for await snap in s.status { self?.ble = snap }
                })
                s.start()
            case .demoFile:
                guard let url = demoURL else {
                    error = "demo_sounds.wav missing from the app bundle"
                    return
                }
                let s = try WavFileBoxSource(url: url)
                file = s
                source = s
                s.start()
            }
            let engine = DetectionEngine(source: source, classifier: classifier, rules: rules)
            tasks.append(Task.detached { await engine.run() })
            tasks.append(Task { [weak self] in
                for await snapshot in engine.activeEvents {
                    self?.events = snapshot
                    self?.saveFinished(snapshot)
                }
            })
            let names = nameFeed
            tasks.append(Task { [weak self] in
                var speechEnds = 0
                for await st in engine.statusUpdates {
                    self?.status = st
                    if st.speechEnds != speechEnds {    // someone stopped talking
                        speechEnds = st.speechEnds
                        names.speechEnded()
                    }
                }
            })
            let feed = nameFeed
            tasks.append(Task.detached { for await f in engine.audioFrames { feed.feed(f.samples) } })
            running = true
            error = nil
            updateNameAlerts()
        } catch {
            self.error = "Couldn't start sound detection: \(error)"
        }
    }

    func stop() {
        nameTask?.cancel()
        nameTask = nil
        nameListener = nil
        nameFeed.replace(with: nil)
        nameStatus = nil
        nameAlerts = []
        bleSource?.stop()
        file?.stop()
        for t in tasks { t.cancel() }
        tasks = []
        bleSource = nil
        file = nil
        running = false
        events = []
    }

    /// (Re)starts name alerts from Settings: on when the switch is on and at least one name is
    /// filled in. Needs iOS 26 (Apple's on-device speech-to-text).
    func updateNameAlerts() {
        let d = UserDefaults.standard
        let matcher = NameMatcher(field: d.string(forKey: SettingKey.nameList) ?? "")
        let wanted = running && (d.object(forKey: SettingKey.nameAlerts) as? Bool ?? true) && !matcher.isEmpty
        if wanted, #available(iOS 26.0, *), let listener = nameListener as? NameListener {
            listener.setMatcher(matcher)     // just new names: keep listening, no restart
            return
        }
        nameTask?.cancel()
        nameTask = nil
        nameListener = nil
        nameFeed.replace(with: nil)
        guard wanted else {
            nameStatus = nil
            return
        }
        guard #available(iOS 26.0, *) else {
            nameStatus = "Name alerts need iOS 26"
            return
        }
        nameStatus = "Getting the speech model ready\u{2026}"
        let listener = NameListener(matcher: matcher)
        listener.logTranscripts = d.bool(forKey: SettingKey.logTranscripts)
        nameListener = listener
        nameTask = Task { [weak self] in
            do {
                try await listener.start()
            } catch {
                if !Task.isCancelled { self?.nameStatus = "Name alerts unavailable: \(error)" }
                return
            }
            guard !Task.isCancelled, let self else { await listener.stop(); return }
            self.nameFeed.replace(with: listener)
            self.nameStatus = "Listening for your name"
            await withTaskCancellationHandler {
                for await heard in listener.heard { self.add(heard) }
            } onCancel: {
                Task { await listener.stop() }
            }
        }
    }

    private func add(_ heard: NameHeard) {
        Self.log.info("name heard (\(heard.isFinal ? "final" : "in-progress", privacy: .public))")
        let az = status.azimuthDeg
        nameAlerts.insert(NameAlert(text: heard.text, azimuthDeg: az, at: heard.at), at: 0)
        nameAlerts.removeAll { Date().timeIntervalSince($0.at) > NameAlert.showS }
    }

    /// Name alerts still on screen.
    var activeNameAlerts: [NameAlert] {
        nameAlerts.filter { Date().timeIntervalSince($0.at) <= NameAlert.showS }
    }

    /// One line for the Live screen: where the audio comes from right now.
    var summary: String {
        if let error { return error }
        switch input {
        case .demoFile:
            return "Demo recording through the box pipeline"
        case .boxes:
            switch ble.bluetooth {
            case .poweredOff: return "Bluetooth is off"
            case .unauthorized: return "Allow Bluetooth in Settings to connect the pins"
            case .unsupported: return "This device has no Bluetooth LE"
            default: break
            }
            let connected = ble.boxes.filter { $0.value.state == .connected }.count
            guard connected > 0 else { return "Looking for pins\u{2026}" }
            let from = status.streamingBox.map { " \u{00B7} listening via \($0.rawValue)" } ?? ""
            return "\(connected) of 4 pins connected\(from)"
        }
    }
}

/// Live screen source: the session's events as the screens' `SoundCue`s.
struct LiveCueSource: CueSource {
    var cues: AsyncStream<[SoundCue]> {
        AsyncStream { continuation in
            let task = Task { @MainActor in
                let session = LiveSession.shared
                session.start()
                while !Task.isCancelled {
                    let names = session.activeNameAlerts.prefix(1).map(SoundCue.init(name:))
                    continuation.yield(names + session.events.filter(\.isActive).map(SoundCue.init(event:)))
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

/// Someone said the wearer's name.
struct NameAlert: Identifiable, Sendable {
    static let showS = 6.0
    let id = UUID()
    let text: String            // what was said, e.g. "Hey Avery, come here"
    let azimuthDeg: Float?      // the sound direction when it was heard
    let at: Date
}

/// Hands box audio to the current name listener (swapped when Settings change) off the main actor.
final class NameFeed: @unchecked Sendable {
    private let lock = NSLock()
    private var sink: (any SampleSink)?
    func replace(with s: (any SampleSink)?) { lock.withLock { sink = s } }
    func feed(_ samples: [Int16]) { lock.withLock { sink }?.feed(samples) }
    func speechEnded() { lock.withLock { sink }?.speechEnded() }
}

protocol SampleSink: AnyObject, Sendable {
    func feed(_ samples: [Int16])
    func speechEnded()
}
@available(iOS 26.0, *) extension NameListener: SampleSink {}

extension SoundCue {
    init(name a: NameAlert) {
        self.init(id: a.id.uuidString, title: "Your name", kind: Self.quote(a.text),
                  symbol: "person.wave.2.fill", group: .urgent, azimuthDeg: Double(a.azimuthDeg ?? 0),
                  directionText: a.azimuthDeg == nil ? "Direction unclear" : nil)
    }

    /// What was said, short enough for a chip: "Hey Avery, come h…" in curly quotes.
    static func quote(_ text: String, max: Int = 24) -> String {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return "\u{201C}" + (t.count > max ? t.prefix(max - 1) + "\u{2026}" : t) + "\u{201D}"
    }

    init(event e: SoundEvent) {
        let look = SoundCue.look[e.label] ?? ("Sound", "waveform")
        let group: CueGroup = switch e.label {
        case .speech: .speech
        case _ where e.isUrgent || e.categories.contains(.babies): .urgent
        default: .ambient
        }
        self.init(id: e.id.uuidString, title: look.title,
                  kind: e.label == .speech ? "Voice" : nil, symbol: look.symbol, group: group, label: e.label,
                  azimuthDeg: Double(e.azimuthDeg ?? 0),
                  directionText: e.azimuthDeg == nil ? "Direction unclear" : nil)
    }

    /// Title + SF Symbol per model label.
    static let look: [SoundLabel: (title: String, symbol: String)] = [
        .siren: ("Siren", "light.beacon.max.fill"),
        .alarm: ("Alarm", "alarm.fill"),
        .glassBreak: ("Glass breaking", "wineglass.fill"),
        .carHorn: ("Car horn", "car.fill"),
        .babyCry: ("Baby crying", "figure.and.child.holdinghands"),
        .knock: ("Knock", "door.left.hand.closed"),
        .clap: ("Clap", "hands.clap.fill"),
        .dog: ("Dog bark", "dog.fill"),
        .cat: ("Cat", "cat.fill"),
        .appliance: ("Appliance", "washer.fill"),
        .speech: ("Speech", "bubble.left.fill"),
        .footsteps: ("Footsteps", "figure.walk"),
    ]
}
