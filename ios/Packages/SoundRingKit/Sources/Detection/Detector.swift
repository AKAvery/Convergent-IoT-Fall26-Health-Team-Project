import Foundation

// Swift port of demo/detector.py: the same ring buffer, loudness gate, persistence, "other" veto,
// priority scoring and presets, so the eval harness (ml/eval_pipeline.py) measures what the app does.
// Checked step by step against fixtures/detector/ (DetectionTests). Comparisons that Python does in
// float32 (numpy scalars, NEP 50) are done in Float here; scores and levels in Double.

public let detectorSampleRate = 16_000
/// 0.975 s, what YAMNet expects.
public let yamnetWindow = 15_600

/// Every tunable in the pipeline; defaults = DetectorParams.default() in demo/detector.py.
public struct DetectorParams: Sendable, Equatable, Codable {
    public var hopS = 0.10
    public var bufferS = 1.0
    public var gateDb = -70.0
    public var gateWindowS = 0.10
    public var persist = 5
    public var otherVeto = true
    public var otherVetoMargin = 0.15
    public var vetoExemptPriority = 8
    public var labelMargin = 0.10
    public var loudRefDb = -60.0
    public var loudFloor = 0.2
    public var inputGainDb = 0.0
    public var clipLevel = 0.99
    /// Once a class has fired it stays on while its probability is >= this instead of its
    /// threshold (demo/detector.py `sustain`): speech no longer drops out at every dip.
    public var sustain: [String: Float] = ["speech": 0.5]

    public init() {}

    public var hopSamples: Int { Int((hopS * Double(detectorSampleRate)).rounded()) }
    public var bufferSamples: Int { Int((bufferS * Double(detectorSampleRate)).rounded()) }
}

/// Same tables as demo/detector.py (and ml/config.py).
public enum DetectorTables {
    public static let classPriority: [String: Int] = [
        "siren": 10, "alarm": 10, "glass_break": 8, "car_horn": 9, "baby_cry": 7,
        "knock": 5, "clap": 4, "dog": 3, "cat": 2, "appliance": 2, "speech": 2, "footsteps": 1]

    /// Which detected sounds count as alerts (shown big). nil = no filter.
    public static let presets: [String: Set<String>?] = [
        "all": nil,
        "safety": ["siren", "alarm", "car_horn", "glass_break"],
        "babies": ["baby_cry"],
        "privacy": ["speech"],
        "household": ["knock", "dog", "cat", "appliance", "footsteps", "clap"],
    ]

    public static func priority(_ label: String) -> Int { classPriority[label] ?? 1 }
}

public let otherLabel = "other"

public struct Hit: Sendable, Equatable {
    public let label: String
    public let conf: Float
    public let score: Double
}

/// One update of the detector, like the dict `Detector.process` returns in Python.
public struct DetectorStep: Sendable {
    public var ready = false
    public var rmsDb = -180.0
    public var levelDb = -180.0
    public var peakDb = -100.0
    public var clipFraction = 0.0
    public var gated = true
    public var label: String?
    public var conf: Float = 0
    public var top3: [(String, Float)] = []
    public var hits: [Hit] = []
    public var alerts: [Hit] = []
    public var probs: [Float]?
}

func dbfs(_ x: Double) -> Double { 20 * log10(x + 1e-9) }

public final class Detector {
    public let params: DetectorParams
    public let names: [String]
    public let thresholds: [Float]
    public var preset: String { didSet { precondition(DetectorTables.presets[preset] != nil, "unknown preset \(preset)") } }
    public private(set) var streak: [Int]

    private let classifier: any SoundClassifier
    private let hop: Int
    private let nBuf: Int
    private let gain: Float
    private let iOther: Int?
    private var buf: [Float]
    private var filled = 0

    public init(params: DetectorParams = DetectorParams(), classifier: any SoundClassifier,
                thresholds: [Float]? = nil, preset: String = "all") {
        self.params = params
        self.classifier = classifier
        self.names = classifier.labels
        self.thresholds = thresholds ?? classifier.thresholds
        precondition(DetectorTables.presets[preset] != nil, "unknown preset \(preset)")
        self.preset = preset
        hop = params.hopSamples
        nBuf = params.bufferSamples
        gain = Float(pow(10, params.inputGainDb / 20))
        iOther = names.firstIndex(of: otherLabel)
        buf = [Float](repeating: 0, count: nBuf)
        streak = [Int](repeating: 0, count: names.count)
    }

    /// Samples per update (1600 = 0.1 s at the defaults).
    public var hopSamples: Int { hop }

    public func reset() {
        buf = [Float](repeating: 0, count: nBuf)
        filled = 0
        streak = [Int](repeating: 0, count: names.count)
    }

    /// What the gate and the loudness factor look at: the loudest 0.1 s RMS in the buffer.
    public func levelDb() -> Double {
        let w = Int((params.gateWindowS * Double(detectorSampleRate)).rounded())
        if w <= 0 || w >= buf.count { return dbfs(rms(buf[...])) }
        let n = buf.count / w
        let start = buf.count - n * w
        var best = 0.0
        for k in 0..<n { best = max(best, rms(buf[(start + k * w)..<(start + (k + 1) * w)])) }
        return dbfs(best)
    }

    /// Feed `hopSamples` new mono samples at 16 kHz (float, full scale = 1).
    public func process(_ block: [Float]) -> DetectorStep {
        let b = gain == 1 ? block : block.map { $0 * gain }
        if !b.isEmpty {
            if b.count >= nBuf {
                buf = Array(b.suffix(nBuf))
            } else {
                buf.removeFirst(b.count)
                buf.append(contentsOf: b)
            }
            filled = min(filled + b.count, nBuf)
        }
        var st = DetectorStep()
        st.ready = filled >= nBuf
        st.rmsDb = dbfs(rms(buf[...]))
        st.levelDb = levelDb()
        if !b.isEmpty {
            let peak = b.reduce(Float(0)) { max($0, abs($1)) }
            st.peakDb = dbfs(Double(peak))
            st.clipFraction = Double(b.filter { abs($0) >= Float(params.clipLevel) }.count) / Double(b.count)
        }
        guard st.ready, st.levelDb >= params.gateDb else { return st }
        st.gated = false
        let p = classifier.probs(window: buf)
        st.probs = p
        (st.hits, st.top3) = decide(p, levelDb: st.levelDb)
        let (top, alerts) = pickLabel(st.hits, p)
        st.alerts = alerts
        if let top { st.label = top.label; st.conf = top.conf }
        return st
    }

    /// Decision rule on one probability vector; updates the per-class streaks.
    public func decide(_ p: [Float], levelDb: Double) -> (hits: [Hit], top3: [(String, Float)]) {
        let loud = min(1.0, max(params.loudFloor, (levelDb - params.loudRefDb) / 30))
        let otherTop = iOther != nil && argmax(p) == iOther
        var hits: [(Int, Hit)] = []
        for (i, name) in names.enumerated() {
            var thr = thresholds[i]
            if streak[i] >= params.persist, let s = params.sustain[name] { thr = min(thr, s) }   // already on
            if name == otherLabel || p[i] < thr { streak[i] = 0; continue }
            if params.otherVeto, otherTop, let io = iOther,
               DetectorTables.priority(name) < params.vetoExemptPriority,
               p[i] < p[io] + Float(params.otherVetoMargin) {
                streak[i] = 0; continue
            }
            streak[i] += 1
            if streak[i] < params.persist { continue }
            let score = Double(DetectorTables.priority(name)) * Double(p[i]) * loud
            hits.append((i, Hit(label: name, conf: p[i], score: score)))
        }
        // Python's sorted() is stable: equal scores keep label order.
        let sorted = hits.sorted { $0.1.score != $1.1.score ? $0.1.score > $1.1.score : $0.0 < $1.0 }.map(\.1)
        let order = p.indices.sorted { p[$0] != p[$1] ? p[$0] > p[$1] : $0 < $1 }.prefix(3)
        return (sorted, order.map { (names[$0], p[$0]) })
    }

    /// Big label = top alert for the active preset, withheld when a rival class is almost as
    /// likely. Safety classes are never withheld.
    public func pickLabel(_ hits: [Hit], _ p: [Float], preset: String? = nil) -> (Hit?, [Hit]) {
        let allowed = DetectorTables.presets[preset ?? self.preset] ?? nil
        let alerts = hits.filter { allowed == nil || allowed!.contains($0.label) }
        guard let top = alerts.first else { return (nil, alerts) }
        if params.labelMargin > 0, DetectorTables.priority(top.label) < params.vetoExemptPriority,
           let i = names.firstIndex(of: top.label) {
            let rivals = names.indices.filter { names[$0] != otherLabel && $0 != i }.map { p[$0] }
            if let best = rivals.max(), p[i] < best + Float(params.labelMargin) { return (nil, alerts) }
        }
        return (top, alerts)
    }
}

private func rms(_ x: ArraySlice<Float>) -> Double {
    guard !x.isEmpty else { return 0 }
    var s = 0.0
    for v in x { s += Double(v) * Double(v) }
    return (s / Double(x.count)).squareRoot()
}

private func argmax(_ p: [Float]) -> Int {
    var best = 0
    for i in p.indices where p[i] > p[best] { best = i }
    return best
}
