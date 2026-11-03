import CryptoKit
import Foundation
import Testing
@testable import Detection

// fixtures/detector/ holds the Python detector's step-by-step output on 30 clips
// (ml/export_detector_fixtures.py). Two checks:
//   replay   the Swift Detector fed the recorded probabilities: gate, streaks, veto, hits, labels
//            must match Python exactly (runs everywhere, no TFLite needed)
//   model    the Swift Detector with the real TFLiteClassifier: probabilities within 1e-4 and the
//            same decisions (iPhone / Simulator only, where TensorFlowLiteC exists)

let repoDir = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
let detectorFixtures = repoDir.appendingPathComponent("fixtures/detector")

struct FixtureManifest: Decodable {
    struct Clip: Decodable { let id: String; let json: String; let audio: String }
    struct Models: Decodable { let sha256: [String: String] }
    struct DetectorBlock: Decodable {
        let labels: [String]
        let thresholds: [String: Double]
        let class_priority: [String: Int]
        let presets: [String: [String]?]
        let hop_samples: Int
        let buffer_samples: Int
        let window_samples: Int
    }
    let clips: [Clip]
    let models: Models
    let detector: DetectorBlock
}

struct FixtureClip: Decodable {
    struct HitJ: Decodable { let label: String; let conf: Double; let score: Double }
    struct Step: Decodable {
        let i: Int
        let ready: Bool
        let level_db: Double
        let gated: Bool
        let probs: [Double]?
        let hits: [HitJ]
        let label: String?
        let streak: [Int]
        let label_by_preset: [String: String?]?
        let fragile: [String]?
    }
    let id: String
    let steps: [Step]
}

func loadManifest() throws -> FixtureManifest {
    try JSONDecoder().decode(FixtureManifest.self,
                             from: Data(contentsOf: detectorFixtures.appendingPathComponent("manifest.json")))
}

let fixtureClipIDs: [String] = (try? loadManifest().clips.map(\.id)) ?? []

func loadClip(_ id: String) throws -> (FixtureClip, [Float]) {
    let clip = try JSONDecoder().decode(FixtureClip.self,
                                        from: Data(contentsOf: detectorFixtures.appendingPathComponent("\(id).json")))
    let raw = try Data(contentsOf: detectorFixtures.appendingPathComponent("\(id).bin"))
    let audio = raw.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }   // little-endian float32
    return (clip, audio)
}

/// Hands the detector whatever probabilities the test sets for the current step.
final class ReplayClassifier: SoundClassifier {
    let labels: [String]
    let thresholds: [Float]
    var next: [Float]?
    var unexpectedCalls = 0

    init(labels: [String], thresholds: [Float]) {
        self.labels = labels
        self.thresholds = thresholds
    }

    func probs(window: [Float]) -> [Float] {
        guard let p = next else { unexpectedCalls += 1; return [Float](repeating: 0, count: labels.count) }
        return p
    }
}

/// Compares one Swift step with the Python step; returns a description of every mismatch.
func compare(_ st: DetectorStep, _ py: FixtureClip.Step, _ det: Detector, probsTolerance: Float? = nil) -> [String] {
    var bad: [String] = []
    let fragile = Set(py.fragile ?? [])
    if st.gated != py.gated, !fragile.contains("gate") { bad.append("gated \(st.gated) vs \(py.gated)") }
    if abs(st.levelDb - py.level_db) > 0.01 { bad.append(String(format: "level %.4f vs %.4f", st.levelDb, py.level_db)) }
    if let tol = probsTolerance, let p = st.probs, let q = py.probs {
        let d = zip(p, q).map { abs($0 - Float($1)) }.max() ?? 0
        if d > tol { bad.append("probs differ by \(d)") }
    }
    if !fragile.isEmpty { return bad }   // decisions here sit within float error of a boundary
    let swiftHits = st.hits.map(\.label), pyHits = py.hits.map(\.label)
    if swiftHits != pyHits { bad.append("hits \(swiftHits) vs \(pyHits)") }
    for (a, b) in zip(st.hits, py.hits) where abs(a.score - b.score) > 1e-4 * max(1, abs(b.score)) {
        bad.append("score \(a.label) \(a.score) vs \(b.score)")
    }
    if det.streak != py.streak { bad.append("streak \(det.streak) vs \(py.streak)") }
    if st.label != py.label { bad.append("label \(st.label ?? "-") vs \(py.label ?? "-")") }
    if let byPreset = py.label_by_preset, let p = st.probs {
        for (preset, expected) in byPreset {
            let got = det.pickLabel(st.hits, p, preset: preset).0?.label
            if got != expected { bad.append("\(preset) label \(got ?? "-") vs \(expected ?? "-")") }
        }
    }
    return bad
}

@Suite struct DetectorFixtureTests {
    @Test func tablesMatchPython() throws {
        let m = try loadManifest().detector
        #expect(DetectorTables.classPriority == m.class_priority)
        #expect(Set(DetectorTables.presets.keys) == Set(m.presets.keys))
        for (k, v) in m.presets { #expect(DetectorTables.presets[k]! == v.map(Set.init)) }
        let p = DetectorParams()
        #expect(p.hopSamples == m.hop_samples)
        #expect(p.bufferSamples == m.buffer_samples)
        #expect(yamnetWindow == m.window_samples)
    }

    /// The bundled model files are the ones the fixtures (and the eval harness) were made with.
    @Test func bundledModelsMatchFixtures() throws {
        let m = try loadManifest()
        for (file, sha) in m.models.sha256 {
            let data = try Data(contentsOf: ModelFiles.directory.appendingPathComponent(file))
            let got = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            #expect(got == sha, "\(file) in Detection/Resources/Models differs from ml/models")
        }
        let labels = try ModelFiles.labels()
        #expect(labels == m.detector.labels)
        let thr = try ModelFiles.thresholds(for: labels)
        #expect(thr == labels.map { Float(m.detector.thresholds[$0]!) })
    }

    @Test(arguments: fixtureClipIDs)
    func replayMatchesPython(id: String) throws {
        let m = try loadManifest().detector
        let (clip, audio) = try loadClip(id)
        let cls = ReplayClassifier(labels: m.labels, thresholds: m.labels.map { Float(m.thresholds[$0]!) })
        let det = Detector(classifier: cls)
        let hop = det.hopSamples
        #expect(audio.count / hop == clip.steps.count)
        var problems: [String] = []
        for py in clip.steps {
            cls.next = py.probs?.map { Float($0) }
            let st = det.process(Array(audio[(py.i * hop)..<((py.i + 1) * hop)]))
            for p in compare(st, py, det) { problems.append("step \(py.i): \(p)") }
        }
        #expect(cls.unexpectedCalls == 0, "classifier called on a step Python gated")
        #expect(problems.isEmpty, "\(problems.prefix(5).joined(separator: "; "))")
    }
}

#if canImport(TensorFlowLiteC)
@Suite(.serialized) struct TFLiteParityTests {
    static let classifier = try? TFLiteClassifier()

    @Test func loads() throws {
        #expect(Self.classifier != nil)
    }

    @Test(arguments: fixtureClipIDs)
    func modelMatchesPython(id: String) throws {
        let cls = try #require(Self.classifier)
        let (clip, audio) = try loadClip(id)
        let det = Detector(classifier: cls)
        let hop = det.hopSamples
        var problems: [String] = []
        var maxDiff: Float = 0
        for py in clip.steps {
            let st = det.process(Array(audio[(py.i * hop)..<((py.i + 1) * hop)]))
            if let p = st.probs, let q = py.probs {
                maxDiff = max(maxDiff, zip(p, q).map { abs($0 - Float($1)) }.max() ?? 0)
            }
            for p in compare(st, py, det, probsTolerance: 1e-4) { problems.append("step \(py.i): \(p)") }
        }
        print("[parity] \(id): max |prob diff| = \(maxDiff), \(problems.count) problem steps")
        #expect(problems.isEmpty, "\(problems.prefix(5).joined(separator: "; "))")
    }
}
#endif
