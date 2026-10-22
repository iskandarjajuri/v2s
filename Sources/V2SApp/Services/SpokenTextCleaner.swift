import Foundation

/// Cleans recognized speech before it is handed to the translator, so fillers and stutters
/// are not translated word for word ("Yah, um, hari ini, ..."). It is meant for translation
/// input only; the subtitle's original text keeps what the speaker actually said.
///
/// Every rule is deliberately conservative: a filler only counts when it stands alone
/// (あの人, なんか食べたい and まあまあ are real words and stay untouched).
enum SpokenTextCleaner {
    static func clean(_ text: String, languageCode: String) -> String {
        let cleaned: String
        switch languageCode {
        case "ja": cleaned = cleanJapanese(text)
        case "en": cleaned = cleanEnglish(text)
        default: cleaned = text
        }
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never hand the translator an empty string because everything looked like a filler.
        return trimmed.isEmpty ? text : trimmed
    }

    // MARK: Japanese

    /// Fillers that mean nothing else. Safe even when glued to the next word.
    private static let unambiguousJapaneseFillers = [
        "えーっと", "えーと", "ええと", "えっと", "えぇと", "あのー", "あのぉ", "うーんと", "うーん", "んー", "あー"
    ]
    /// Real words as well as fillers: only dropped when set off by a delimiter or the string end.
    private static let ambiguousJapaneseFillers = ["えー", "あの", "その", "まあ", "なんか", "ま"]

    private static func cleanJapanese(_ text: String) -> String {
        var result = text
        result = normalizeWidthAndSpacing(result)
        result = removeJapaneseFillers(result)
        result = collapseJapaneseRepeats(result)
        result = normalizeJapaneseNumerals(result)
        return result
    }

    private static let delimiterClass = "、，,。.！？!? 　"

    private static func removeJapaneseFillers(_ text: String) -> String {
        var result = text

        // Unambiguous fillers at a token start: after the string start or a delimiter.
        let unambiguous = unambiguousJapaneseFillers.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        result = replace(
            #"(?:^|(?<=[\#(delimiterClass)]))(?:\#(unambiguous))[、，,]?\s*"#,
            in: result, with: ""
        )

        // Ambiguous fillers need a delimiter (or the end of the text) right after them.
        let ambiguous = ambiguousJapaneseFillers.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
        result = replace(
            #"(?:^|(?<=[\#(delimiterClass)]))(?:\#(ambiguous))(?:[、，,]\s*|\s+|$)"#,
            in: result, with: ""
        )

        // A filler left dangling between delimiters: "今日は、その、会議が" → "今日は、会議が".
        result = replace(
            #"(?<=[、，,])(?:\#(unambiguous)|\#(ambiguous))[、，,]"#,
            in: result, with: ""
        )
        return result
    }

    /// "私は、私は、行きます" → "私は、行きます"; "今日は今日は" → "今日は". Only whole delimited
    /// phrases or a kanji/katakana word plus particle repeat; reduplicated words such as
    /// いろいろ or ときどき are never touched.
    private static func collapseJapaneseRepeats(_ text: String) -> String {
        var result = text
        result = replace(#"([^、，,。\s]{1,12})[、，,]\s*\1(?=[、，,。\s]|$)"#, in: result, with: "$1")
        result = replace(#"([\p{Han}\p{Katakana}ー]{1,8}[はがもをにでと])\1"#, in: result, with: "$1")
        return result
    }

    private static func normalizeWidthAndSpacing(_ text: String) -> String {
        var result = text
        // Full-width ASCII letters and digits → half-width; kana and CJK punctuation stay as they are.
        result = narrowASCIIOnly(result)
        // The recognizer sometimes leaves a stray space between kana/kanji and a number ("歩いて 5分").
        result = replace(#"(?<=[\p{Han}\p{Hiragana}\p{Katakana}]) +(?=\d)"#, in: result, with: "")
        result = replace(#"(?<=\d) +(?=[\p{Han}\p{Hiragana}\p{Katakana}])"#, in: result, with: "")
        return result
    }

    private static func narrowASCIIOnly(_ text: String) -> String {
        String(text.unicodeScalars.map { scalar -> Character in
            if (0xFF01...0xFF5E).contains(scalar.value), let narrowed = Unicode.Scalar(scalar.value - 0xFEE0) {
                return Character(narrowed)
            }
            return Character(scalar)
        })
    }

    // MARK: Numerals

    private static let kanjiDigits: [Character: Int] = [
        "〇": 0, "一": 1, "二": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9
    ]
    private static let counterPattern = "年|月|日|時|分|秒|円|個|人|台|歳|回|%|％|パーセント|キロ|メートル"

    /// 五分 → 5分, 二千二十五年 → 2025年. A lone 一 is never converted (一緒, 一人), and 十分
    /// stays as is because it also means "enough".
    private static func normalizeJapaneseNumerals(_ text: String) -> String {
        let pattern = #"([〇一二三四五六七八九十百千万]+)(?=\#(counterPattern))"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let nsText = text as NSString
        var result = ""
        var location = 0
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            result += nsText.substring(with: NSRange(location: location, length: match.range.location - location))
            let numeral = nsText.substring(with: match.range)
            let following = nsText.substring(from: match.range.location + match.range.length)
            if numeral == "一" || (numeral == "十" && following.hasPrefix("分")) || isInsideWord(before: result) {
                result += numeral
            } else if let value = kanjiNumeralValue(numeral) {
                result += String(value)
            } else {
                result += numeral
            }
            location = match.range.location + match.range.length
        }
        result += nsText.substring(from: location)
        return result
    }

    /// True when the text just before the numeral is a kanji that would make it part of a compound
    /// (e.g. 第三回). Keeps the conversion to plain "number + counter" phrases.
    private static func isInsideWord(before prefix: String) -> Bool {
        guard let last = prefix.last else { return false }
        return last == "第"
    }

    private static func kanjiNumeralValue(_ text: String) -> Int? {
        var total = 0
        var section = 0
        var pending: Int?
        for character in text {
            if let digit = kanjiDigits[character] {
                pending = (pending ?? 0) * 10 + digit
                continue
            }
            switch character {
            case "十": section += (pending ?? 1) * 10; pending = nil
            case "百": section += (pending ?? 1) * 100; pending = nil
            case "千": section += (pending ?? 1) * 1_000; pending = nil
            case "万":
                total += (section + (pending ?? 0)) * 10_000
                section = 0; pending = nil
            default: return nil
            }
        }
        return total + section + (pending ?? 0)
    }

    // MARK: English

    private static func cleanEnglish(_ text: String) -> String {
        var result = text
        result = replace(#"(?i)(?:^|(?<=[\s,.!?]))(?:u+m+|u+h+|er+m?|hm+|mm+)\b(?:,|\.\.\.)?\s*(?=\S|$)"#, in: result, with: "")
        result = replace(#"\s{2,}"#, in: result, with: " ")
        result = replace(#"\s+([,.!?])"#, in: result, with: "$1")
        return result
    }

    // MARK: Helpers

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(location: 0, length: (text as NSString).length),
            withTemplate: template
        )
    }
}

