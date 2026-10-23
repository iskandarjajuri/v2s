import XCTest
@testable import v2s

final class TranscriptExporterTests: XCTestCase {
    private let utc = TimeZone(identifier: "UTC")!
    private let base = Date(timeIntervalSince1970: 1_761_100_000) // 2025-10-22 02:26:40 UTC

    private func entry(_ offset: TimeInterval, _ source: String, _ translation: String, name: String = "") -> TranscriptEntry {
        TranscriptEntry(id: UUID(), sourceText: source, translatedText: translation, timestamp: base.addingTimeInterval(offset), sourceName: name)
    }

    func testMarkdownHasHeaderTimestampsAndBothLanguages() {
        let text = TranscriptExporter.markdown(
            entries: [entry(0, "おはようございます。", "Selamat pagi."), entry(5, "会議を始めます。", "Rapat dimulai.", name: "Zoom")],
            header: .init(title: "Transkrip", sourceLanguageName: "日本語", targetLanguageName: "Indonesia", exportedAt: base),
            timeZone: utc
        )
        XCTAssertEqual(text, """
        # Transkrip

        - 日本語 → Indonesia
        - 2025-10-22 02:26

        **02:26:40**

        おはようございます。

        > Selamat pagi.

        **02:26:45** · Zoom

        会議を始めます。

        > Rapat dimulai.

        """)
    }

    func testMarkdownSkipsEmptyEntriesAndUntranslatedDuplicates() {
        let text = TranscriptExporter.markdown(
            entries: [entry(0, "", ""), entry(1, "Hello", "Hello")],
            header: .init(title: "T", sourceLanguageName: "EN", targetLanguageName: "EN", exportedAt: base),
            timeZone: utc
        )
        XCTAssertFalse(text.contains("02:26:40"))
        XCTAssertFalse(text.contains("> Hello"))
        XCTAssertTrue(text.contains("Hello"))
    }

    func testMarkdownQuotesEveryLineOfAMultiLineTranslation() {
        let text = TranscriptExporter.markdown(
            entries: [entry(0, "a", "satu\ndua")],
            header: .init(title: "T", sourceLanguageName: "A", targetLanguageName: "B", exportedAt: base),
            timeZone: utc
        )
        XCTAssertTrue(text.contains("> satu\n> dua"))
    }

    func testPlainTextPutsTranslationOnItsOwnIndentedLine() {
        let text = TranscriptExporter.plainText(
            entries: [entry(0, "こんにちは", "Halo"), entry(2, "はい", "Ya")],
            timeZone: utc
        )
        XCTAssertEqual(text, "[02:26:40] こんにちは\n    Halo\n[02:26:42] はい\n    Ya")
    }
}
