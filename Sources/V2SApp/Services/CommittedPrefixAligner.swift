import Foundation

/// Finds where already-committed text ends inside a newer, possibly rewritten transcript.
///
/// The recognizer keeps re-sending one growing transcript and may revise earlier words
/// (昼ご飯 → 昼ごはん, "3.5 percent" → "3.5%"). An exact prefix match then fails and the
/// whole history would be treated as new text and shown twice. Comparing on letters and
/// digits only, with a bounded edit distance, tolerates those rewrites.
///
/// Only the tail of the committed text is matched, inside a window around where it should
/// end. A session can commit thousands of characters before the recognizer finalizes, and a
/// full alignment of that history on every result would cost far more than it is worth.
enum CommittedPrefixAligner {
    /// Committed characters (letters/digits only) that must line up.
    private static let tailLimit = 160

    /// - Returns: the part of `fullText` after the counterpart of `committed`, or nil when
    ///   the two do not line up closely enough to trust.
    static func remainder(
        of fullText: String,
        afterCommitted committed: String,
        maxDistanceRatio: Double = 0.2
    ) -> String? {
        let committedChars = comparableCharacters(of: committed)
        let n = committedChars.count
        guard n >= 4 else { return nil }

        var fullChars: [Character] = []
        var fullEnds: [String.Index] = []
        for index in fullText.indices {
            let character = fullText[index]
            guard isComparable(character) else { continue }
            fullChars.append(lowered(character))
            fullEnds.append(fullText.index(after: index))
        }
        let m = fullChars.count
        guard m >= n / 2 else { return nil }

        let tail = Array(committedChars.suffix(tailLimit))
        // Rewrites move the end of the committed text by a few percent at most.
        let slack = 40 + n / 20
        let windowStart = max(0, n - tail.count - slack)
        let windowEnd = min(m, n + slack)
        guard windowEnd - windowStart >= tail.count / 2 else { return nil }
        let window = Array(fullChars[windowStart..<windowEnd])

        // Approximate substring match: the tail may start anywhere in the window, so the
        // first row is all zeros. previous[j] ends up as the cost of the best match of the
        // whole tail that ends at window position j.
        var previous = [Int](repeating: 0, count: window.count + 1)
        var current = [Int](repeating: 0, count: window.count + 1)
        for i in 1...tail.count {
            current[0] = i
            if window.isEmpty == false {
                for j in 1...window.count {
                    let substitution = previous[j - 1] + (tail[i - 1] == window[j - 1] ? 0 : 1)
                    current[j] = min(substitution, previous[j] + 1, current[j - 1] + 1)
                }
            }
            swap(&previous, &current)
        }

        let expectedEnd = n - windowStart
        var bestEnd = 0
        var bestDistance = Int.max
        for j in 1...max(window.count, 1) where j <= window.count {
            let distance = previous[j]
            if distance < bestDistance
                || (distance == bestDistance && abs(j - expectedEnd) < abs(bestEnd - expectedEnd)) {
                bestDistance = distance
                bestEnd = j
            }
        }

        guard bestEnd > 0, Double(bestDistance) / Double(tail.count) <= maxDistanceRatio else { return nil }

        let splitIndex = fullEnds[windowStart + bestEnd - 1]
        let rest = fullText[splitIndex...]
        let start = rest.firstIndex { character in
            !character.unicodeScalars.allSatisfy { leadingTrim.contains($0) }
        } ?? rest.endIndex
        return String(rest[start...])
    }

    private static let leadingTrim = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "。、，．,.!?！？"))

    private static func isComparable(_ character: Character) -> Bool {
        character.isLetter || character.isNumber
    }

    private static func comparableCharacters(of text: String) -> [Character] {
        text.filter(isComparable).map(lowered)
    }

    private static func lowered(_ character: Character) -> Character {
        String(character).lowercased().first ?? character
    }
}
