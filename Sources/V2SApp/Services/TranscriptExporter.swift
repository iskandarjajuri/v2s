import Foundation

/// Renders the two-language transcript as text or Markdown for saving and sharing.
enum TranscriptExporter {
    struct Header {
        var title: String
        var sourceLanguageName: String
        var targetLanguageName: String
        var exportedAt: Date
    }

    static func markdown(
        entries: [TranscriptEntry],
        header: Header,
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let timeFormatter = makeTimeFormatter(timeZone: timeZone, locale: locale)
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = "yyyy-MM-dd HH:mm"

        var lines = [
            "# \(header.title)",
            "",
            "- \(header.sourceLanguageName) → \(header.targetLanguageName)",
            "- \(dateFormatter.string(from: header.exportedAt))",
            ""
        ]

        for entry in entries where entry.sourceText.isEmpty == false || entry.translatedText.isEmpty == false {
            lines.append("**\(timeFormatter.string(from: entry.timestamp))**" + sourceNameSuffix(for: entry))
            lines.append("")
            if entry.sourceText.isEmpty == false {
                lines.append(entry.sourceText)
                lines.append("")
            }
            if entry.translatedText.isEmpty == false, entry.translatedText != entry.sourceText {
                for line in entry.translatedText.split(separator: "\n", omittingEmptySubsequences: false) {
                    lines.append("> \(line)")
                }
                lines.append("")
            }
        }

        return lines.joined(separator: "\n")
    }

    static func plainText(
        entries: [TranscriptEntry],
        timeZone: TimeZone = .current,
        locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let timeFormatter = makeTimeFormatter(timeZone: timeZone, locale: locale)
        return entries
            .filter { $0.sourceText.isEmpty == false || $0.translatedText.isEmpty == false }
            .map { entry in
                var block = "[\(timeFormatter.string(from: entry.timestamp))]"
                if entry.sourceText.isEmpty == false { block += " \(entry.sourceText)" }
                if entry.translatedText.isEmpty == false, entry.translatedText != entry.sourceText {
                    block += "\n    \(entry.translatedText)"
                }
                return block
            }
            .joined(separator: "\n")
    }

    private static func sourceNameSuffix(for entry: TranscriptEntry) -> String {
        entry.sourceName.isEmpty ? "" : " · \(entry.sourceName)"
    }

    private static func makeTimeFormatter(timeZone: TimeZone, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }
}
