import Foundation

/// One name or term that the recognizer tends to get wrong, matched by how it sounds.
struct ReadingGlossaryEntry: Codable, Equatable, Hashable, Identifiable, Sendable {
    /// The spelling to put in the subtitle (e.g. 石橋誠).
    var term: String
    /// How the term is read, in kana or romaji (e.g. いしばしまこと). Optional for Latin-script terms.
    var reading: String
    /// Language code the entry applies to ("ja", "en", "id"); nil applies to every language.
    var language: String?

    var id: String { "\(language ?? "*")|\(term)|\(reading)" }
}

/// JSON file format for import/export. Versioned so the format can grow.
struct ReadingGlossaryFile: Codable, Equatable {
    var version: Int
    var entries: [ReadingGlossaryEntry]

    static let currentVersion = 1

    init(entries: [ReadingGlossaryEntry]) {
        self.version = Self.currentVersion
        self.entries = entries
    }

    enum FileError: LocalizedError {
        case unsupportedVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedVersion(let version):
                return "Unsupported glossary file version \(version)"
            }
        }
    }

    static func decode(from data: Data) throws -> ReadingGlossaryFile {
        let file = try JSONDecoder().decode(ReadingGlossaryFile.self, from: data)
        guard file.version <= currentVersion else { throw FileError.unsupportedVersion(file.version) }
        return file
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

/// Corrects names and terms in recognized text by sound rather than by spelling, before the
/// text is shown or translated. Japanese speech is full of homophones, so the recognizer
/// often writes the right sound with the wrong kanji (石橋 → 石箸). A spelling-based
/// replace can never fix that; comparing readings can.
struct ReadingGlossary: Sendable {
    private struct Prepared {
        let entry: ReadingGlossaryEntry
        let key: [Character]
    }

    private let japanese: [Prepared]
    private let latin: [Prepared]

    init(entries: [ReadingGlossaryEntry]) {
        var japanese: [Prepared] = []
        var latin: [Prepared] = []
        for entry in entries {
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard term.isEmpty == false else { continue }
            let readingSource = entry.reading.trimmingCharacters(in: .whitespacesAndNewlines)
            if Self.containsJapanese(term) || Self.containsJapanese(readingSource) {
                let key = Self.japaneseKey(of: readingSource.isEmpty ? term : readingSource)
                if key.count >= 2 { japanese.append(Prepared(entry: entry, key: key)) }
            } else {
                let key = Self.latinKey(of: readingSource.isEmpty ? term : readingSource)
                if key.count >= 3 { latin.append(Prepared(entry: entry, key: key)) }
            }
        }
        // Longer readings first so "石橋誠" wins over a shorter overlapping entry.
        self.japanese = japanese.sorted { $0.key.count > $1.key.count }
        self.latin = latin.sorted { $0.key.count > $1.key.count }
    }

    var isEmpty: Bool { japanese.isEmpty && latin.isEmpty }

    func apply(to text: String, languageCode: String) -> String {
        guard isEmpty == false else { return text }
        switch languageCode {
        case "ja":
            return applyJapanese(to: text, languageCode: languageCode)
        default:
            return applyLatin(to: text, languageCode: languageCode)
        }
    }

    // MARK: Japanese

    private struct Token {
        let range: Range<String.Index>
        let key: [Character]
    }

    private func applyJapanese(to text: String, languageCode: String) -> String {
        let entries = japanese.filter { $0.entry.language == nil || $0.entry.language == languageCode }
        guard entries.isEmpty == false else { return text }

        let tokens = Self.japaneseTokens(in: text)
        guard tokens.isEmpty == false else { return text }

        var replacements: [(Range<String.Index>, String)] = []
        var index = 0
        while index < tokens.count {
            var matched = false
            for prepared in entries {
                var joined: [Character] = []
                var end = index
                while end < tokens.count, joined.count < prepared.key.count {
                    joined.append(contentsOf: tokens[end].key)
                    end += 1
                }
                guard end > index, Self.isCloseEnough(joined, prepared.key) else { continue }
                let range = tokens[index].range.lowerBound..<tokens[end - 1].range.upperBound
                if text[range] != prepared.entry.term {
                    replacements.append((range, prepared.entry.term))
                }
                index = end
                matched = true
                break
            }
            if matched == false { index += 1 }
        }

        guard replacements.isEmpty == false else { return text }
        var result = text
        for (range, term) in replacements.reversed() {
            result.replaceSubrange(range, with: term)
        }
        return result
    }

    /// Splits text into pieces that carry a hiragana reading. Uses the system tokenizer so
    /// kanji get their in-context reading instead of one fixed guess.
    private static func japaneseTokens(in text: String) -> [Token] {
        let cfText = text as CFString
        let tokenizer = CFStringTokenizerCreate(
            nil, cfText, CFRange(location: 0, length: CFStringGetLength(cfText)),
            kCFStringTokenizerUnitWordBoundary, Locale(identifier: "ja") as CFLocale
        )
        var tokens: [Token] = []
        while CFStringTokenizerAdvanceToNextToken(tokenizer) != [] {
            let cfRange = CFStringTokenizerGetCurrentTokenRange(tokenizer)
            guard let range = Range(NSRange(location: cfRange.location, length: cfRange.length), in: text) else { continue }
            let surface = String(text[range])
            let latin = CFStringTokenizerCopyCurrentTokenAttribute(tokenizer, kCFStringTokenizerAttributeLatinTranscription) as? String
            let reading = latin.map { Self.japaneseKey(ofRomaji: $0) } ?? Self.japaneseKey(of: surface)
            guard reading.isEmpty == false else { continue }
            tokens.append(Token(range: range, key: reading))
        }
        return tokens
    }

    // MARK: Latin scripts (en, id, …)

    private func applyLatin(to text: String, languageCode: String) -> String {
        let entries = latin.filter { $0.entry.language == nil || $0.entry.language == languageCode }
        guard entries.isEmpty == false else { return text }

        var words: [(range: Range<String.Index>, key: [Character])] = []
        text.enumerateSubstrings(in: text.startIndex..., options: .byWords) { substring, range, _, _ in
            guard let substring else { return }
            words.append((range, Self.latinKey(of: substring)))
        }

        var replacements: [(Range<String.Index>, String)] = []
        var index = 0
        while index < words.count {
            var matched = false
            for prepared in entries {
                var joined: [Character] = []
                var end = index
                while end < words.count, joined.count < prepared.key.count {
                    joined.append(contentsOf: words[end].key)
                    end += 1
                }
                guard end > index, Self.isCloseEnough(joined, prepared.key) else { continue }
                let range = words[index].range.lowerBound..<words[end - 1].range.upperBound
                if text[range] != prepared.entry.term {
                    replacements.append((range, prepared.entry.term))
                }
                index = end
                matched = true
                break
            }
            if matched == false { index += 1 }
        }

        guard replacements.isEmpty == false else { return text }
        var result = text
        for (range, term) in replacements.reversed() {
            result.replaceSubrange(range, with: term)
        }
        return result
    }

    // MARK: Keys

    /// Equal keys, or one edit apart for longer readings (a single mis-heard mora).
    private static func isCloseEnough(_ lhs: [Character], _ rhs: [Character]) -> Bool {
        if lhs == rhs { return true }
        guard rhs.count >= 6, abs(lhs.count - rhs.count) <= 1 else { return false }
        return editDistance(lhs, rhs) <= 1
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                current[j] = min(previous[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1), previous[j] + 1, current[j - 1] + 1)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }

    private static func containsJapanese(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0x3040...0x30FF).contains(scalar.value) || (0x4E00...0x9FFF).contains(scalar.value) || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    /// Reading key for Japanese: hiragana-folded romaji with long vowels and doubled consonants
    /// collapsed so ASR spelling variants of the same sound compare equal.
    private static func japaneseKey(of text: String) -> [Character] {
        let mutable = NSMutableString(string: text)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        return japaneseKey(ofRomaji: mutable as String)
    }

    private static func japaneseKey(ofRomaji romaji: String) -> [Character] {
        var folded = romaji.applyingTransform(.stripDiacritics, reverse: false) ?? romaji
        folded = folded.lowercased()
        var key: [Character] = []
        for character in folded where character.isLetter && character.isASCII {
            // Collapse repeated letters: "tokyo", "toukyou" and "tokyoo" must compare equal.
            if key.last == character { continue }
            key.append(character)
        }
        // ou/oo/uu long vowels: drop the trailing "u" after "o" ("toukyou" → "tokyo").
        var normalized: [Character] = []
        for character in key {
            if character == "u", normalized.last == "o" { continue }
            normalized.append(character)
        }
        return normalized
    }

    /// Phonetic-ish key for Latin-script terms: lowercase, ASCII, similar sounds merged, repeats collapsed.
    private static func latinKey(of text: String) -> [Character] {
        var folded = text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        for (from, to) in [("ph", "f"), ("ck", "k"), ("qu", "kw"), ("x", "ks"), ("c", "k"), ("y", "i"), ("w", "v"), ("z", "s")] {
            folded = folded.replacingOccurrences(of: from, with: to)
        }
        var key: [Character] = []
        for character in folded where character.isLetter && character.isASCII {
            if key.last == character { continue }
            key.append(character)
        }
        return key
    }
}
