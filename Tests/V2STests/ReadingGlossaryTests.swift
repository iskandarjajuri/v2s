import XCTest
@testable import v2s

final class ReadingGlossaryTests: XCTestCase {
    private func glossary(_ pairs: [(String, String)], language: String? = nil) -> ReadingGlossary {
        ReadingGlossary(entries: pairs.map { ReadingGlossaryEntry(term: $0.0, reading: $0.1, language: language) })
    }

    // MARK: Japanese, by sound

    func testFixesHomophoneKanjiBySound() {
        let g = glossary([("石橋誠", "いしばしまこと")])
        XCTAssertEqual(g.apply(to: "担当は石箸誠です", languageCode: "ja"), "担当は石橋誠です")
    }

    func testFixesKatakanaVariantBySound() {
        let g = glossary([("シンフォニクス", "しんふぉにくす")])
        XCTAssertEqual(g.apply(to: "シンフォニックスの製品", languageCode: "ja"), "シンフォニクスの製品")
    }

    func testLeavesTextAloneWhenSpellingAlreadyMatches() {
        let g = glossary([("石橋誠", "いしばしまこと")])
        XCTAssertEqual(g.apply(to: "石橋誠さんが来ました", languageCode: "ja"), "石橋誠さんが来ました")
    }

    func testDoesNotTouchUnrelatedText() {
        let g = glossary([("石橋誠", "いしばしまこと")])
        XCTAssertEqual(g.apply(to: "今日は天気がいいですね", languageCode: "ja"), "今日は天気がいいですね")
    }

    func testEntryScopedToAnotherLanguageIsIgnored() {
        let g = glossary([("石橋誠", "いしばしまこと")], language: "en")
        XCTAssertEqual(g.apply(to: "担当は石箸誠です", languageCode: "ja"), "担当は石箸誠です")
    }

    // MARK: Latin scripts

    func testFixesMisheardEnglishNameBySound() {
        let g = glossary([("Symphonics", "symfonics")])
        XCTAssertEqual(g.apply(to: "We use Symphonix tools", languageCode: "en"), "We use Symphonics tools")
    }

    func testFixesIndonesianNameVariant() {
        let g = glossary([("Iskandar", "iskandar")])
        XCTAssertEqual(g.apply(to: "Terima kasih Iskandarr", languageCode: "id"), "Terima kasih Iskandar")
    }

    func testShortWordsAreNeverFuzzyMatched() {
        let g = glossary([("AI", "ai")])
        XCTAssertEqual(g.apply(to: "I said hi to him", languageCode: "en"), "I said hi to him")
    }

    func testEmptyGlossaryIsANoOp() {
        XCTAssertEqual(ReadingGlossary(entries: []).apply(to: "何でも", languageCode: "ja"), "何でも")
    }

    // MARK: File format

    func testExportedFileRoundTrips() throws {
        let entries = [
            ReadingGlossaryEntry(term: "石橋誠", reading: "いしばしまこと", language: "ja"),
            ReadingGlossaryEntry(term: "Symphonics", reading: "symfonics", language: nil)
        ]
        let data = try ReadingGlossaryFile(entries: entries).encoded()
        XCTAssertEqual(try ReadingGlossaryFile.decode(from: data).entries, entries)
    }

    func testImportRejectsNewerFileVersion() {
        let data = Data(#"{"version": 99, "entries": []}"#.utf8)
        XCTAssertThrowsError(try ReadingGlossaryFile.decode(from: data))
    }

    func testImportRejectsGarbage() {
        XCTAssertThrowsError(try ReadingGlossaryFile.decode(from: Data("not json".utf8)))
    }
}
