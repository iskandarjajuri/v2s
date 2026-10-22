import XCTest
@testable import v2s

final class PunctuationSegmenterTests: XCTestCase {
    private let settings = SegmentationSettings.default

    private func plan(
        _ text: String,
        _ language: SegmentationLanguage = .japanese,
        age: TimeInterval = 1,
        settings: SegmentationSettings? = nil
    ) -> PunctuationSegmenter.Cut? {
        PunctuationSegmenter.plan(
            pending: text,
            language: language,
            pendingAgeSeconds: age,
            settings: settings ?? self.settings
        )
    }

    // MARK: Sentence boundaries

    func testCutsFinishedJapaneseSentenceWhileNextOneIsStillStreaming() throws {
        let cut = try XCTUnwrap(plan("おはようございます。今日もよろ"))
        XCTAssertEqual(cut.committed, "おはようございます。")
        XCTAssertEqual(cut.remaining, "今日もよろ")
        XCTAssertEqual(cut.reason, .sentenceBoundary)
    }

    func testKeepsAllButTheTrailingSentenceWhenSeveralAreFinished() throws {
        let cut = try XCTUnwrap(plan("一つ目です。二つ目です。三つ目の途"))
        XCTAssertEqual(cut.committed, "一つ目です。二つ目です。")
        XCTAssertEqual(cut.remaining, "三つ目の途")
    }

    func testDoesNotCutWhenTheOnlySentenceIsUnfinished() {
        XCTAssertNil(plan("今日は朝から会議があって"))
    }

    func testDoesNotCutWhenTextAlreadyEndsAtTheTerminator() {
        // The recognizer-side fast path owns this case.
        XCTAssertNil(plan("おはようございます。"))
    }

    func testDecimalPointIsNotASentenceBoundary() {
        XCTAssertNil(plan("The price rose by 3.5 percent last quarter", .english))
        XCTAssertNil(plan("価格は3.5パーセント上がりました", .japanese))
    }

    func testTitleAbbreviationIsNotASentenceBoundary() {
        XCTAssertNil(plan("Mr. Smith said the price went up", .english))
    }

    func testEnglishSentenceBoundaryStillCuts() throws {
        let cut = try XCTUnwrap(plan("I went to the office. Then we had a meet", .english))
        XCTAssertEqual(cut.committed, "I went to the office. ")
        XCTAssertEqual(cut.remaining, "Then we had a meet")
    }

    // MARK: Long runs without a sentence end

    private let longJapanese = "今日は朝から会議があって、その後すぐに新しいプロジェクトの打ち合わせに行かなければならないので、昼ご飯を食べる時間"

    func testShortRunIsLeftAloneEvenWithCommas() {
        XCTAssertNil(plan(longJapanese, age: 4))
    }

    func testLongRunCutsAtTheLastCommaThatLeavesATail() throws {
        let cut = try XCTUnwrap(plan(longJapanese, age: 13))
        XCTAssertEqual(cut.reason, .clauseBoundary)
        XCTAssertEqual(cut.committed, "今日は朝から会議があって、その後すぐに新しいプロジェクトの打ち合わせに行かなければならないので、")
        XCTAssertEqual(cut.remaining, "昼ご飯を食べる時間")
    }

    func testClauseCutNeverLeavesTooLittleBehind() {
        // The comma is the last thing said: the tail would be empty, so there is nothing to cut.
        XCTAssertNil(plan("今日は朝から会議があってその後すぐに新しいプロジェクトの打ち合わせに行って、", age: 13))
    }

    func testClauseCutNeedsEnoughTextBeforeTheComma() {
        XCTAssertNil(plan("はい、今日は朝から会議があってその後すぐに新しいプロジェクトの打ち合わせに行きました", age: 13))
    }

    func testCharacterLimitAlsoTriggersWithoutLongDuration() throws {
        let text = String(repeating: "あいうえおかきくけこ", count: 5) + "、" + String(repeating: "さしすせそ", count: 8)
        let cut = try XCTUnwrap(plan(text, age: 2))
        XCTAssertEqual(cut.reason, .clauseBoundary)
        XCTAssertTrue(cut.committed.hasSuffix("、"))
    }

    func testEndingBasedCutOnlyWhenOverlongAndNoComma() throws {
        let text = "今日は朝から会議がありましたけど午後は少し時間が取れたのでそのまま新しいプロジェクトの打ち合わせに向かいました"
        XCTAssertNil(plan(text, age: 13), "an ending cut must wait until the run is clearly overlong")
        let cut = try XCTUnwrap(plan(text, age: 20))
        XCTAssertEqual(cut.reason, .clauseBoundary)
        XCTAssertTrue(cut.committed.hasSuffix("ので"), "got \(cut.committed)")
    }

    func testEndingBasedCutCanBeSwitchedOff() {
        var off = settings
        off.cutAtJapaneseClauseEndings = false
        let text = "今日は朝から会議がありましたけど午後は少し時間が取れたのでそのまま新しいプロジェクトの打ち合わせに向かいました"
        XCTAssertNil(plan(text, age: 20, settings: off))
    }

    func testEnglishCommaCutRequiresSpaceAndSkipsThousandsSeparators() throws {
        let numbers = "We sold 1,000 units and then the numbers kept climbing every single week of the quarter without any pause at all"
        XCTAssertNil(plan(numbers, .english, age: 13))

        let clause = "So yesterday I went to the office early, finished the report, and then had a long meeting with the new client about"
        let cut = try XCTUnwrap(plan(clause, .english, age: 13))
        XCTAssertEqual(cut.committed, "So yesterday I went to the office early, finished the report,")
        XCTAssertEqual(cut.remaining, " and then had a long meeting with the new client about")
    }

    func testDisabledSettingsNeverCut() {
        var off = settings
        off.isEnabled = false
        XCTAssertNil(plan("おはようございます。今日もよろ", settings: off))
        XCTAssertNil(plan(longJapanese, age: 40, settings: off))
    }

    // MARK: Settings

    func testSettingsDecodeFromEmptyObject() throws {
        let decoded = try JSONDecoder().decode(SegmentationSettings.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, .default)
    }

    func testSettingsClampOutOfRangeValues() {
        let wild = SegmentationSettings(maxContinuousSpeechSeconds: 900, stableLeadingMs: 1)
        XCTAssertEqual(wild.clamped.maxContinuousSpeechSeconds, 30)
        XCTAssertEqual(wild.clamped.stableLeadingMs, 80)
    }
}
