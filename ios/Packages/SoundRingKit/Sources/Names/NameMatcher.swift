import Foundation

/// Finds the wearer's name in a transcript: whole words only, so "Avery" matches "Avery,",
/// "AVERY!" and "Avery's", but not "every", "bravery" or "Averyville".
///
/// Each entry in `names` is a name, a nickname, or a sound-alike the speech-to-text tends to write
/// instead (e.g. "a worry" for "Avery"); multi-word entries must appear as consecutive words.
public struct NameMatcher: Sendable, Equatable {
    /// Every entry as normalized words, longest first, duplicates and empty entries removed.
    public let phrases: [[String]]

    public init(names: [String]) {
        var seen = Set<[String]>()
        phrases = names.map(Self.words).filter { !$0.isEmpty && seen.insert($0).inserted }
            .sorted { $0.count > $1.count }
    }

    /// Splits a settings field like "Avery, Ave; a worry" into entries.
    public init(field: String) {
        self.init(names: field.split(whereSeparator: { ",;\n".contains($0) }).map(String.init))
    }

    public var isEmpty: Bool { phrases.isEmpty }

    /// The entry that matched first in the text (words joined by spaces), or nil.
    public func firstMatch(in text: String) -> String? { matches(in: text).first }

    /// Every place a name occurs, in order, as the entry that matched; a longer entry wins where
    /// two overlap ("a worry" over "worry").
    public func matches(in text: String) -> [String] { matches(inWords: Self.words(text)).map(\.name) }

    /// Same, on words already split with `words(_:)`; `start` is the index of the first word.
    public func matches(inWords w: [String]) -> [(name: String, start: Int)] {
        var out: [(name: String, start: Int)] = []
        var i = 0
        while i < w.count {
            if let p = phrases.first(where: { i + $0.count <= w.count && Array(w[i..<(i + $0.count)]) == $0 }) {
                out.append((p.joined(separator: " "), i))
                i += p.count
            } else {
                i += 1
            }
        }
        return out
    }

    /// Lowercased words without accents or punctuation; a possessive "'s" (or a bare trailing
    /// apostrophe) is dropped, so "Avery's" and "James'" are the names.
    public static func words(_ text: String) -> [String] {
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "\u{2019}", with: "'")
        return folded.split(whereSeparator: { !($0.isLetter || $0.isNumber || $0 == "'") }).compactMap { raw in
            var w = Substring(raw)
            while w.first == "'" { w = w.dropFirst() }
            if w.hasSuffix("'s") { w = w.dropLast(2) }
            while w.last == "'" { w = w.dropLast() }
            return w.isEmpty ? nil : String(w)
        }
    }
}
