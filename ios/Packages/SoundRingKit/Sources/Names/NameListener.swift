import AVFoundation
import CoreMedia
import Foundation
import OSLog
import Speech

/// One time the wearer's name was heard.
public struct NameHeard: Sendable, Equatable {
    public let name: String       // the matcher entry that matched
    public let text: String       // what the speech-to-text wrote, e.g. "Hey Avery, come here"
    public let at: Date
    public let isFinal: Bool      // false = matched on an in-progress (volatile) result, the fast path

    public init(name: String, text: String, at: Date, isFinal: Bool) {
        self.name = name
        self.text = text
        self.at = at
        self.isFinal = isFinal
    }
}

public enum NameListenerError: Error, Equatable {
    case unavailable              // no on-device speech-to-text on this device
    case unsupportedLocale
}

/// Listens for the wearer's name in the box audio with Apple's on-device speech-to-text
/// (SpeechAnalyzer + SpeechTranscriber, iOS 26 / macOS 26). Audio never leaves the device.
///
/// Feed it the same 16 kHz mono samples the detector gets (`feed`). It matches every result,
/// in-progress ones included, against a `NameMatcher` and reports each spoken utterance once.
/// One listener runs once: `stop()` ends its streams; make a new one to listen again.
@available(iOS 26.0, macOS 26.0, *)
public final class NameListener: @unchecked Sendable {
    public let heard: AsyncStream<NameHeard>
    /// Every transcript (in-progress and final), newest only: for a "what Halo hears" line.
    public let transcripts: AsyncStream<String>

    /// The box audio, which is also what the speech-to-text prefers (checked on macOS 26.5).
    public static let format = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000,
                                             channels: 1, interleaved: false)!
    /// Samples per buffer handed to the analyzer (100 ms).
    static let chunk = 1600

    private let heardOut: AsyncStream<NameHeard>.Continuation
    private let textOut: AsyncStream<String>.Continuation
    private let lock = NSLock()
    private var matcher: NameMatcher
    private var inputOut: AsyncStream<AnalyzerInput>.Continuation?
    private var analyzer: SpeechAnalyzer?
    private var resultsTask: Task<Void, Never>?
    private var pending: [Int16] = []
    /// Timing diagnostics (Console, subsystem edu.utexas.convergent.soundring, category names):
    /// audio time = samples fed so far / 16 kHz, which is also the analyzer's clock.
    private var fedSamples = 0
    private var firstFeed: Date?
    private var alertAudioS: Double?
    static let log = Logger(subsystem: "edu.utexas.convergent.soundring", category: "names")
    /// Developer switch: also log every finished transcript in plain text. Off by default: it
    /// writes what people around the wearer say into the system log.
    public var logTranscripts = false
    /// Names already alerted that the current in-progress text still holds. Apple's in-progress
    /// result covers everything since the last finished segment and replaces the one before. A
    /// call can be alerted from an in-progress result and then finish in a *later* segment (seen
    /// live: "Hello, Avery?" alerted twice, 4 s apart), so a finished segment only takes off the
    /// names it actually contains; the rest carry over. An in-progress result that holds fewer
    /// names than counted lowers the count, so a stale carry-over can't swallow the next call.
    private var reportedInSegment = 0
    /// Names in one finished result closer than this (audio time) are one call ("Avery! Avery!").
    static let mergeS = 1.5

    public init(matcher: NameMatcher) {
        self.matcher = matcher
        (heard, heardOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(8))
        (transcripts, textOut) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    public func setMatcher(_ m: NameMatcher) { lock.withLock { matcher = m } }

    /// Checks support and downloads the speech model if needed (once per device, may take a while
    /// on first use). Returns the locale it will use: the device's, else US English.
    @discardableResult
    public static func prepare(locale preferred: Locale = .current) async throws -> Locale {
        guard SpeechTranscriber.isAvailable else { throw NameListenerError.unavailable }
        var found = await SpeechTranscriber.supportedLocale(equivalentTo: preferred)
        if found == nil { found = await SpeechTranscriber.supportedLocale(equivalentTo: Locale(identifier: "en-US")) }
        guard let locale = found else { throw NameListenerError.unsupportedLocale }
        if let request = try await AssetInventory.assetInstallationRequest(supporting: [transcriber(locale)]) {
            try await request.downloadAndInstall()
        }
        return locale
    }

    static func transcriber(_ locale: Locale) -> SpeechTranscriber {
        SpeechTranscriber(locale: locale, transcriptionOptions: [],
                          reportingOptions: [.volatileResults], attributeOptions: [.audioTimeRange])
    }

    private var used = false

    public func start(locale preferred: Locale = .current) async throws {
        guard lock.withLock({ () -> Bool in defer { used = true }; return !used }) else { return }
        let locale = try await Self.prepare(locale: preferred)
        let module = Self.transcriber(locale)
        let analyzer = SpeechAnalyzer(modules: [module],
                                      options: .init(priority: .userInitiated, modelRetention: .lingering))
        try await analyzer.prepareToAnalyze(in: Self.format)
        // Up to 60 s queued if the model falls behind (or a test feeds faster than real time).
        let (input, inputOut) = AsyncStream.makeStream(of: AnalyzerInput.self, bufferingPolicy: .bufferingNewest(600))
        try await analyzer.start(inputSequence: input)
        let task = Task { [weak self] in
            do {
                for try await r in module.results { self?.handle(r) }
            } catch {}
        }
        lock.withLock {
            self.analyzer = analyzer
            self.inputOut = inputOut
            self.resultsTask = task
            pending = []
            reportedInSegment = 0
        }
    }

    /// 16 kHz mono samples, any amount (e.g. one 320-sample box frame).
    public func feed(_ samples: [Int16]) {
        let chunks: [[Int16]] = lock.withLock {
            guard inputOut != nil else { return [] }
            if firstFeed == nil { firstFeed = Date() }
            fedSamples += samples.count
            pending.append(contentsOf: samples)
            var out: [[Int16]] = []
            while pending.count >= Self.chunk {
                out.append(Array(pending.prefix(Self.chunk)))
                pending.removeFirst(Self.chunk)
            }
            return out
        }
        for c in chunks {
            guard let buf = AVAudioPCMBuffer(pcmFormat: Self.format, frameCapacity: AVAudioFrameCount(c.count)) else { continue }
            buf.frameLength = AVAudioFrameCount(c.count)
            c.withUnsafeBufferPointer { buf.int16ChannelData![0].update(from: $0.baseAddress!, count: c.count) }
            _ = lock.withLock { inputOut?.yield(AnalyzerInput(buffer: buf)) }
        }
    }

    /// Call when someone stops talking (our detector's speech hit just ended). In a quiet room
    /// Apple's model notices the pause itself, but under room noise it only reports every ~3.9 s
    /// (measured 2026-11-05). Committing everything heard so far makes the name show up right after
    /// the sentence instead: 3.3 -> 1.8 s on the demo. Committing on a timer instead cuts words in
    /// half ("Avery" became "."), so only do it at the end of speech.
    public func speechEnded() {
        let (analyzer, fed): (SpeechAnalyzer?, Int) = lock.withLock { (self.analyzer, fedSamples) }
        guard let analyzer, fed > 0 else { return }
        Self.log.info("speech ended: committing through \(Double(fed) / 16000, format: .fixed(precision: 2)) s")
        Task { try? await analyzer.finalize(through: CMTime(value: CMTimeValue(fed), timescale: 16000)) }
    }

    /// Finishes the current utterance (its results still arrive) and stops.
    public func stop() async {
        let (analyzer, inputOut): (SpeechAnalyzer?, AsyncStream<AnalyzerInput>.Continuation?) = lock.withLock {
            defer { self.analyzer = nil; self.inputOut = nil; pending = [] }
            return (self.analyzer, self.inputOut)
        }
        inputOut?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        await resultsTask?.value
        heardOut.finish()
        textOut.finish()
    }

    private func handle(_ r: SpeechTranscriber.Result) {
        let text = String(r.text.characters)
        let isFinal = r.resultsFinalizationTime >= r.range.end
        textOut.yield(text)
        if isFinal, logTranscripts { Self.log.info("heard: \(text, privacy: .public)") }
        // Each word with its start time. Only finished results carry real times (in-progress
        // ones report 0, checked on macOS 26.5), which is all we use them for.
        var words: [String] = [], times: [Double] = []
        for run in r.text.runs {
            let t = run.audioTimeRange?.start.seconds ?? 0
            for w in NameMatcher.words(String(r.text[run.range].characters)) {
                words.append(w)
                times.append(t)
            }
        }
        let hits: [NameHeard] = lock.withLock {
            let found = matcher.matches(inWords: words)
            let already = reportedInSegment
            let audioS = Double(fedSamples) / 16000
            let wallS = firstFeed.map { Date().timeIntervalSince($0) } ?? 0
            guard isFinal else {
                reportedInSegment = found.count
                guard found.count > already else { return [] }
                alertAudioS = audioS
                Self.log.info("""
                    alert (in-progress) with \(audioS, format: .fixed(precision: 2)) s of audio in, \
                    \(wallS, format: .fixed(precision: 2)) s since the first audio
                    """)
                return [NameHeard(name: found[already].name, text: text, at: Date(), isFinal: false)]
            }
            if let a = alertAudioS, let m = found.first {
                Self.log.info("""
                    name was spoken at \(times[m.start], format: .fixed(precision: 2)) s: alert came \
                    \(a - times[m.start], format: .fixed(precision: 2)) s later (audio time)
                    """)
            }
            alertAudioS = nil
            reportedInSegment = max(0, already - found.count)
            var out: [NameHeard] = []
            var lastT = -Double.infinity
            for (k, m) in found.enumerated() {
                let t = times[m.start]
                defer { lastT = t }
                guard k >= already, t - lastT >= Self.mergeS else { continue }
                Self.log.info("""
                    alert (final) for a name spoken at \(t, format: .fixed(precision: 2)) s: \
                    \(audioS - t, format: .fixed(precision: 2)) s later (audio time)
                    """)
                out.append(NameHeard(name: m.name, text: text, at: Date(), isFinal: true))
            }
            return out
        }
        for h in hits { heardOut.yield(h) }
    }
}
