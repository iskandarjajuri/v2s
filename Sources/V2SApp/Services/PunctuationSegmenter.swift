import Foundation

/// User-tunable knobs for how the live transcript is cut into subtitle segments.
struct SegmentationSettings: Codable, Equatable, Sendable {
    /// Master switch. Off restores the previous behaviour (commit only on a sentence end
    /// followed by a pause, or on VAD/ASR silence).
    var isEnabled: Bool
    /// After this much uninterrupted speech without a sentence end, a clause boundary
    /// (、 or a Japanese clause ending) becomes an acceptable place to cut.
    var maxContinuousSpeechSeconds: Double
    /// How long the leading sentences must stay unchanged before they are committed while
    /// the speaker is already on the next sentence.
    var stableLeadingMs: Int
    /// Allows cutting at けど/ので/から… when a long run has no 、 at all.
    var cutAtJapaneseClauseEndings: Bool

    static let `default` = SegmentationSettings(
        isEnabled: true,
        maxContinuousSpeechSeconds: 12,
        stableLeadingMs: 250,
        cutAtJapaneseClauseEndings: true
    )

    init(
        isEnabled: Bool = SegmentationSettings.default.isEnabled,
        maxContinuousSpeechSeconds: Double = SegmentationSettings.default.maxContinuousSpeechSeconds,
        stableLeadingMs: Int = SegmentationSettings.default.stableLeadingMs,
        cutAtJapaneseClauseEndings: Bool = SegmentationSettings.default.cutAtJapaneseClauseEndings
    ) {
        self.isEnabled = isEnabled
        self.maxContinuousSpeechSeconds = maxContinuousSpeechSeconds
        self.stableLeadingMs = stableLeadingMs
        self.cutAtJapaneseClauseEndings = cutAtJapaneseClauseEndings
    }

    // Tolerant decoder so settings files written before this field existed still load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SegmentationSettings.default
        isEnabled = (try? c.decodeIfPresent(Bool.self, forKey: .isEnabled)) ?? d.isEnabled
        maxContinuousSpeechSeconds = (try? c.decodeIfPresent(Double.self, forKey: .maxContinuousSpeechSeconds))
            ?? d.maxContinuousSpeechSeconds
        stableLeadingMs = (try? c.decodeIfPresent(Int.self, forKey: .stableLeadingMs)) ?? d.stableLeadingMs
        cutAtJapaneseClauseEndings = (try? c.decodeIfPresent(Bool.self, forKey: .cutAtJapaneseClauseEndings))
            ?? d.cutAtJapaneseClauseEndings
    }

    /// Keeps hand-edited or stale values inside a range the planner can reason about.
    var clamped: SegmentationSettings {
        SegmentationSettings(
            isEnabled: isEnabled,
            maxContinuousSpeechSeconds: min(max(maxContinuousSpeechSeconds, 4), 30),
            stableLeadingMs: min(max(stableLeadingMs, 80), 1_000),
            cutAtJapaneseClauseEndings: cutAtJapaneseClauseEndings
        )
    }
}

enum SegmentationLanguage: Equatable, Sendable {
    case japanese
    case english
    case other
}

/// Decides where an in-progress transcript may be cut into a committed part and a
/// remainder that keeps streaming. Pure and synchronous so every rule is unit-testable.
enum PunctuationSegmenter {
    enum Reason: Equatable, Sendable {
        case sentenceBoundary
        case clauseBoundary
    }

    struct Cut: Equatable, Sendable {
        let committed: String
        let remaining: String
        let reason: Reason
    }

    private static let clauseSeparators: Set<Character> = ["、", "，"]
    private static let japaneseClauseEndings = [
        "ましたが", "でしたが", "ですが", "ますが", "けれども", "けれど", "けど",
        "ですし", "ますし", "ていて", "でして", "ので", "から"
    ]

    /// Characters a run must reach before a clause cut is considered ("long enough to be
    /// worth cutting") and how much text must remain after the cut ("still being revised").
    private struct Limits {
        let maxChars: Int
        let minCommittedChars: Int
        let minRemainingChars: Int
    }

    private static func limits(for language: SegmentationLanguage) -> Limits {
        switch language {
        case .japanese: return Limits(maxChars: 80, minCommittedChars: 12, minRemainingChars: 6)
        case .english, .other: return Limits(maxChars: 180, minCommittedChars: 30, minRemainingChars: 20)
        }
    }

    static func plan(
        pending: String,
        language: SegmentationLanguage,
        pendingAgeSeconds: TimeInterval,
        settings: SegmentationSettings
    ) -> Cut? {
        guard settings.isEnabled else { return nil }
        let text = pending.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.isEmpty == false else { return nil }

        if let cut = sentenceCut(in: pending) {
            return cut
        }

        let limit = limits(for: language)
        let isLong = pendingAgeSeconds >= settings.maxContinuousSpeechSeconds || text.count >= limit.maxChars
        guard isLong else { return nil }

        if let cut = clauseCut(in: pending, language: language, limit: limit, allowEndings: false) {
            return cut
        }

        // No 、 at all: only fall back to ending-based cuts once the run is clearly overlong.
        let isOverlong = pendingAgeSeconds >= settings.maxContinuousSpeechSeconds * 1.4
            || text.count >= Int(Double(limit.maxChars) * 1.4)
        guard language == .japanese, settings.cutAtJapaneseClauseEndings, isOverlong else { return nil }
        return clauseCut(in: pending, language: language, limit: limit, allowEndings: true)
    }

    /// Everything before the trailing (still unfinished) sentence, when the sentences before
    /// it really end in a terminator. A terminator that closes the whole text is not handled
    /// here: that case is already committed by the recognizer-side fast path.
    private static func sentenceCut(in pending: String) -> Cut? {
        let nsText = pending as NSString
        let ranges = SentenceBoundaryHeuristics.sentenceRanges(in: nsText)
        guard ranges.count >= 2,
              let trailing = ranges.last,
              trailing.location > 0 else {
            return nil
        }

        let committed = nsText.substring(to: trailing.location)
        let remaining = nsText.substring(from: trailing.location)
        let trimmedCommitted = committed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedCommitted.isEmpty == false,
              remaining.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              SentenceBoundaryHeuristics.endsWithLikelySentenceTerminator(in: trimmedCommitted) else {
            return nil
        }

        return Cut(committed: committed, remaining: remaining, reason: .sentenceBoundary)
    }

    private static func clauseCut(
        in pending: String,
        language: SegmentationLanguage,
        limit: Limits,
        allowEndings: Bool
    ) -> Cut? {
        let characters = Array(pending)
        var best: Int?

        for index in characters.indices {
            let cutAfter: Int?
            if allowEndings {
                cutAfter = endingEnd(in: characters, at: index)
            } else if isClauseSeparator(characters, at: index, language: language) {
                cutAfter = index + 1
            } else {
                cutAfter = nil
            }

            guard let cutAfter else { continue }
            let committedCount = characters[..<cutAfter].filter { !$0.isWhitespace }.count
            let remainingCount = characters[cutAfter...].filter { !$0.isWhitespace }.count
            guard committedCount >= limit.minCommittedChars, remainingCount >= limit.minRemainingChars else {
                continue
            }
            best = cutAfter
        }

        guard let best else { return nil }
        let committed = String(characters[..<best])
        let remaining = String(characters[best...])
        return Cut(committed: committed, remaining: remaining, reason: .clauseBoundary)
    }

    /// 、/， always separate clauses; an ASCII comma only does when it is followed by a space
    /// and is not a thousands separator ("1,000").
    private static func isClauseSeparator(_ characters: [Character], at index: Int, language: SegmentationLanguage) -> Bool {
        let character = characters[index]
        if clauseSeparators.contains(character) {
            return true
        }
        guard character == "," else { return false }
        if index > 0, index + 1 < characters.count,
           characters[index - 1].isNumber, characters[index + 1].isNumber {
            return false
        }
        return index + 1 < characters.count && characters[index + 1].isWhitespace
    }

    /// If one of the Japanese clause endings finishes at `index`, returns the position just
    /// after it. Only the longest ending that starts here counts.
    private static func endingEnd(in characters: [Character], at index: Int) -> Int? {
        for ending in japaneseClauseEndings {
            let ending = Array(ending)
            let end = index + ending.count
            if end <= characters.count, Array(characters[index..<end]) == ending {
                return end
            }
        }
        return nil
    }
}
