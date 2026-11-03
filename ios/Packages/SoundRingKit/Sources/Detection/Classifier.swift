import Foundation
#if canImport(TensorFlowLiteC)
import TensorFlowLiteC
#endif

/// Audio window -> one sigmoid probability per class. The real one is `TFLiteClassifier`; tests
/// replay recorded probabilities through the same protocol.
public protocol SoundClassifier: AnyObject {
    var labels: [String] { get }
    var thresholds: [Float] { get }
    /// Probabilities for the last `yamnetWindow` samples of `window`.
    func probs(window: [Float]) -> [Float]
}

/// The model files bundled with Detection: copies of ml/models/ (YAMNet embedding, our trained head,
/// labels, the thresholds tuned with the eval harness). DetectionTests checks they still match the
/// hashes recorded in fixtures/detector/manifest.json.
public enum ModelFiles {
    public static var directory: URL {
        Bundle.module.url(forResource: "Models", withExtension: nil)!
    }

    public static func labels(in dir: URL = directory) throws -> [String] {
        try JSONDecoder().decode([String].self, from: Data(contentsOf: dir.appendingPathComponent("labels.json")))
    }

    /// Per-class thresholds in label order; 0.5 for a class missing from the file (like Python).
    public static func thresholds(for labels: [String], in dir: URL = directory) throws -> [Float] {
        let t = try JSONDecoder().decode([String: Double].self,
                                         from: Data(contentsOf: dir.appendingPathComponent("thresholds.json")))
        return labels.map { Float(t[$0] ?? 0.5) }
    }
}

/// Peak-normalise to 0.5 and take the last 0.975 s, exactly like `Classifier.probs` in Python.
public func yamnetInput(_ mono: [Float]) -> [Float] {
    var w = mono.count >= yamnetWindow ? Array(mono.suffix(yamnetWindow))
                                       : mono + [Float](repeating: 0, count: yamnetWindow - mono.count)
    // Python normalises the whole buffer before cutting the window, so the peak is over all of it.
    let peak = mono.reduce(Float(0)) { max($0, abs($1)) }
    if peak > 0 { for i in w.indices { w[i] = w[i] / peak * 0.5 } }
    return w
}

#if canImport(TensorFlowLiteC)
public enum TFLiteError: Error, CustomStringConvertible {
    case load(String), allocate(String), invoke(String), shape(String)
    public var description: String {
        switch self {
        case .load(let s): "can't load model \(s)"
        case .allocate(let s): "can't allocate tensors for \(s)"
        case .invoke(let s): "inference failed in \(s)"
        case .shape(let s): s
        }
    }
}

/// One TFLite model with a float32 input and output.
final class TFLiteModel {
    private let model: OpaquePointer
    private let interpreter: OpaquePointer
    private let xnnpack: UnsafeMutablePointer<TfLiteDelegate>?
    let name: String

    init(url: URL, threads: Int32) throws {
        name = url.lastPathComponent
        guard let m = TfLiteModelCreateFromFile(url.path) else { throw TFLiteError.load(name) }
        let options = TfLiteInterpreterOptionsCreate()
        TfLiteInterpreterOptionsSetNumThreads(options, threads)
        // XNNPACK, like the Python interpreter the eval harness and fixtures use: same float
        // kernels, so the probabilities match theirs (and it is the faster CPU path).
        var xo = TfLiteXNNPackDelegateOptionsDefault()
        xo.num_threads = threads
        xnnpack = TfLiteXNNPackDelegateCreate(&xo)
        if let xnnpack { TfLiteInterpreterOptionsAddDelegate(options, xnnpack) }
        defer { TfLiteInterpreterOptionsDelete(options) }
        guard let i = TfLiteInterpreterCreate(m, options) else {
            TfLiteModelDelete(m); throw TFLiteError.load(name)
        }
        model = m
        interpreter = i
        guard TfLiteInterpreterAllocateTensors(i) == kTfLiteOk else { throw TFLiteError.allocate(name) }
    }

    deinit {
        TfLiteInterpreterDelete(interpreter)
        if let xnnpack { TfLiteXNNPackDelegateDelete(xnnpack) }
        TfLiteModelDelete(model)
    }

    var inputCount: Int { TfLiteTensorByteSize(TfLiteInterpreterGetInputTensor(interpreter, 0)) / 4 }

    func run(_ input: [Float]) throws -> [Float] {
        let t = TfLiteInterpreterGetInputTensor(interpreter, 0)
        guard TfLiteTensorByteSize(t) == input.count * 4 else {
            throw TFLiteError.shape("\(name): input has \(TfLiteTensorByteSize(t) / 4) floats, got \(input.count)")
        }
        let copied = input.withUnsafeBytes { TfLiteTensorCopyFromBuffer(t, $0.baseAddress, $0.count) }
        guard copied == kTfLiteOk, TfLiteInterpreterInvoke(interpreter) == kTfLiteOk else {
            throw TFLiteError.invoke(name)
        }
        guard let o = TfLiteInterpreterGetOutputTensor(interpreter, 0) else { throw TFLiteError.invoke(name) }
        var out = [Float](repeating: 0, count: TfLiteTensorByteSize(o) / 4)
        _ = out.withUnsafeMutableBytes { TfLiteTensorCopyToBuffer(o, $0.baseAddress, $0.count) }
        return out
    }
}

/// Frozen YAMNet embedding (TFLite) -> our trained 13-class multi-label head. Not thread-safe:
/// keep one per detector and call it from one task at a time.
public final class TFLiteClassifier: SoundClassifier {
    public let labels: [String]
    public let thresholds: [Float]
    private let embed: TFLiteModel
    private let head: TFLiteModel

    public init(directory: URL = ModelFiles.directory, threads: Int32 = 2) throws {
        labels = try ModelFiles.labels(in: directory)
        thresholds = try ModelFiles.thresholds(for: labels, in: directory)
        embed = try TFLiteModel(url: directory.appendingPathComponent("yamnet_embedding_metadata.tflite"), threads: threads)
        head = try TFLiteModel(url: directory.appendingPathComponent("sound_head.tflite"), threads: 1)
        guard embed.inputCount == yamnetWindow else {
            throw TFLiteError.shape("YAMNet expects \(embed.inputCount) samples, not \(yamnetWindow)")
        }
    }

    public func probs(window: [Float]) -> [Float] {
        do {
            return try head.run(try embed.run(yamnetInput(window)))
        } catch {
            assertionFailure("\(error)")
            return [Float](repeating: 0, count: labels.count)
        }
    }
}
#endif
