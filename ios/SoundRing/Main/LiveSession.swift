import Detection
import Foundation
import Input
import Models

/// The real pipeline behind the Live and Pins screens: the 4 boxes over BLE (or, in the Simulator,
/// a demo WAV through the same ADPCM path), YAMNet + our head, direction, events. Started the first
/// time a screen needs it and kept running while the app is open.
@MainActor @Observable
final class LiveSession {
    static let shared = LiveSession()

    enum Input: Equatable {
        case boxes                 // real boxes over Bluetooth
        case demoFile              // Simulator: no CoreBluetooth, so a demo recording
    }

    private(set) var input: Input
    private(set) var events: [SoundEvent] = []
    private(set) var ble = BLESnapshot()
    private(set) var status = DetectionStatus()
    private(set) var error: String?
    private(set) var running = false

    private var bleSource: BLEBoxSource?
    private var file: WavFileBoxSource?
    private var tasks: [Task<Void, Never>] = []

    private init() {
        #if targetEnvironment(simulator)
        input = .demoFile
        #else
        input = .boxes
        #endif
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
                guard let url = Bundle.main.url(forResource: "demo_sounds", withExtension: "wav") else {
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
                for await snapshot in engine.activeEvents { self?.events = snapshot }
            })
            tasks.append(Task { [weak self] in
                for await st in engine.statusUpdates { self?.status = st }
            })
            running = true
            error = nil
        } catch {
            self.error = "Couldn't start sound detection: \(error)"
        }
    }

    func stop() {
        bleSource?.stop()
        file?.stop()
        for t in tasks { t.cancel() }
        tasks = []
        bleSource = nil
        file = nil
        running = false
        events = []
    }

    /// One line for the Live screen: where the audio comes from right now.
    var summary: String {
        if let error { return error }
        switch input {
        case .demoFile:
            return "Simulator: demo recording through the box pipeline"
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
                    continuation.yield(session.events.filter(\.isActive).map(SoundCue.init(event:)))
                    try? await Task.sleep(for: .milliseconds(100))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

extension SoundCue {
    init(event e: SoundEvent) {
        let look = SoundCue.look[e.label] ?? ("Sound", "waveform")
        let group: CueGroup = switch e.label {
        case .speech: .speech
        case _ where e.isUrgent || e.categories.contains(.babies): .urgent
        default: .ambient
        }
        self.init(id: e.id.uuidString, title: look.title,
                  kind: e.label == .speech ? "Voice" : nil, symbol: look.symbol, group: group,
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
