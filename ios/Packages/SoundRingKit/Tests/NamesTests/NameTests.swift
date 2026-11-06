import Foundation
import Testing
@testable import Names
import Input

@Suite struct NameMatcherTests {
    let avery = NameMatcher(field: "Avery, Ave; a worry")

    @Test func wholeWordsOnly() {
        #expect(avery.firstMatch(in: "Hey Avery, come here") == "avery")
        #expect(avery.firstMatch(in: "AVERY!") == "avery")
        #expect(avery.firstMatch(in: "Is that Avery's bag?") == "avery")
        #expect(avery.firstMatch(in: "Is that Avery\u{2019}s bag?") == "avery")
        for text in ["I go there every day", "Everybody get in", "It takes bravery", "Averyville",
                     "very nice", "Avenue", "", "  ,, "] {
            #expect(avery.firstMatch(in: text) == nil, "\(text)")
        }
    }

    @Test func multiWordSoundAlikes() {
        #expect(avery.firstMatch(in: "Is that a worry bag?") == "a worry")
        #expect(avery.firstMatch(in: "a big worry") == nil)        // not consecutive
        #expect(avery.firstMatch(in: "Ave, wait up") == "ave")
    }

    @Test func everyOccurrence() {
        #expect(avery.matches(in: "Avery! Avery, a worry, every") == ["avery", "avery", "a worry"])
        #expect(NameMatcher(names: ["worry", "a worry"]).matches(in: "a worry") == ["a worry"])
        #expect(avery.matches(in: "") == [])
    }

    @Test func accentsAndCase() {
        let m = NameMatcher(names: ["José", "Zoë"])
        #expect(m.firstMatch(in: "jose, over here") == "jose")
        #expect(m.firstMatch(in: "ZOE") == "zoe")
    }

    @Test func fieldParsing() {
        #expect(NameMatcher(field: " , ;").isEmpty)
        #expect(NameMatcher(field: "Avery,avery, AVERY").phrases == [["avery"]])
        #expect(NameMatcher(field: "Kai\nKy").phrases.count == 2)
    }
}

/// Apple's speech-to-text on audio made with the Mac's `say`, streamed in like box audio.
/// macOS 26 only; skipped where the speech model isn't installed (it downloads on first use).
@Suite(.serialized) struct NameListenerTests {
    static func spoken(_ text: String) throws -> [Int16]? {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("soundring-names-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let aiff = dir.appendingPathComponent("a.aiff").path, wav = dir.appendingPathComponent("a.wav").path
        for (tool, args) in [("/usr/bin/say", ["-v", "Samantha", "-o", aiff, text]),
                             ("/usr/bin/afconvert", ["-f", "WAVE", "-d", "LEI16@16000", "-c", "1", aiff, wav])] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            guard (try? p.run()) != nil else { return nil }
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
        }
        return try WAV.readMono16k(URL(fileURLWithPath: wav))
    }

    @available(macOS 26.0, *)
    static func run(_ texts: String..., names: String) async throws -> [NameHeard]? {
        let silence = [Int16](repeating: 0, count: 4 * 16000)
        var all = silence
        for t in texts {
            guard let speech = try spoken(t) else { return nil }
            all += speech + silence
        }
        let listener = NameListener(matcher: NameMatcher(field: names))
        do { try await listener.start(locale: Locale(identifier: "en-US")) } catch { return nil }
        for frame in stride(from: 0, to: all.count, by: 320) {
            listener.feed(Array(all[frame..<min(frame + 320, all.count)]))
        }
        await listener.stop()                  // finishes `heard` once the last result is in
        var got: [NameHeard] = []
        for await h in listener.heard { got.append(h) }
        return got
    }

    @Test func hearsTheName() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard let got = try await Self.run("Hey Avery, can you come here?", names: "Avery") else { return }
        #expect(got.count == 1, "\(got)")      // in-progress and final results of one utterance: one alert
        #expect(got.first?.name == "avery")
    }

    /// Two calls a few seconds apart are two alerts (in-progress results cover all unfinished
    /// audio, so this is where a naive de-duplication would swallow the second one).
    @Test func twoCallsTwoAlerts() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard let got = try await Self.run("Avery.", "Hey Avery, come here.", names: "Avery") else { return }
        #expect(got.count == 2, "\(got)")
    }

    @Test func ignoresSoundAlikes() async throws {
        guard #available(macOS 26.0, *) else { return }
        guard let got = try await Self.run("I go there every day, it is very nice.", names: "Avery") else { return }
        #expect(got.isEmpty, "\(got)")
    }
}
