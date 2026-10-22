import XCTest
@testable import v2s

final class SpokenTextCleanerTests: XCTestCase {
    private func ja(_ text: String) -> String { SpokenTextCleaner.clean(text, languageCode: "ja") }
    private func en(_ text: String) -> String { SpokenTextCleaner.clean(text, languageCode: "en") }

    // MARK: Fillers

    func testRemovesLeadingFillersFollowedByAComma() {
        XCTAssertEqual(ja("えーっと、今日は会議があります"), "今日は会議があります")
        XCTAssertEqual(ja("えー、あの、今日は遅れました"), "今日は遅れました")
        XCTAssertEqual(ja("まあ、仕方ないですね"), "仕方ないですね")
    }

    func testRemovesFillersBetweenClauses() {
        XCTAssertEqual(ja("今日は、その、会議が長引いて、えっと、遅れました"), "今日は、会議が長引いて、遅れました")
    }

    func testRemovesUnambiguousFillerEvenWithoutAComma() {
        XCTAssertEqual(ja("えっと今日は遅れます"), "今日は遅れます")
        XCTAssertEqual(ja("あのー今日は遅れます"), "今日は遅れます")
    }

    func testKeepsWordsThatMerelyStartLikeAFiller() {
        XCTAssertEqual(ja("あの人は先生です"), "あの人は先生です")
        XCTAssertEqual(ja("なんか食べたい"), "なんか食べたい")
        XCTAssertEqual(ja("まあまあです"), "まあまあです")
        XCTAssertEqual(ja("その本を読みました"), "その本を読みました")
    }

    func testKeepsTextThatIsOnlyAFiller() {
        XCTAssertEqual(ja("えーっと"), "えーっと")
        XCTAssertEqual(ja("あの"), "あの")
    }

    // MARK: Repetition

    func testCollapsesDelimitedStutter() {
        XCTAssertEqual(ja("私は、私は、行きます"), "私は、行きます")
    }

    func testCollapsesRepeatedWordWithParticle() {
        XCTAssertEqual(ja("今日は今日は会議です"), "今日は会議です")
    }

    func testKeepsReduplicatedWords() {
        XCTAssertEqual(ja("いろいろありました"), "いろいろありました")
        XCTAssertEqual(ja("ときどき雨が降ります"), "ときどき雨が降ります")
        XCTAssertEqual(ja("人々が集まりました"), "人々が集まりました")
    }

    // MARK: Numbers and spacing

    func testRemovesStraySpaceBeforeNumber() {
        XCTAssertEqual(ja("駅から歩いて 5分くらい"), "駅から歩いて5分くらい")
    }

    func testNarrowsFullWidthDigitsAndLetters() {
        XCTAssertEqual(ja("価格は３５００円です"), "価格は3500円です")
        XCTAssertEqual(ja("ＡＩを使います"), "AIを使います")
    }

    func testConvertsKanjiNumeralsBeforeCounters() {
        XCTAssertEqual(ja("五分待ってください"), "5分待ってください")
        XCTAssertEqual(ja("二千二十五年の十月二十二日"), "2025年の10月22日")
        XCTAssertEqual(ja("十万円です"), "100000円です")
        XCTAssertEqual(ja("三万五千円です"), "35000円です")
    }

    func testLeavesAmbiguousNumeralsAlone() {
        XCTAssertEqual(ja("一緒に行きましょう"), "一緒に行きましょう")
        XCTAssertEqual(ja("十分に休んでください"), "十分に休んでください")
        XCTAssertEqual(ja("一人で行きます"), "一人で行きます")
        XCTAssertEqual(ja("第三回の会議"), "第三回の会議")
    }

    // MARK: English and others

    func testRemovesEnglishFillers() {
        XCTAssertEqual(en("Um, so yesterday I, uh, went to the office"), "so yesterday I, went to the office")
        XCTAssertEqual(en("Hmm, that is interesting"), "that is interesting")
    }

    func testEnglishKeepsWordsContainingFillerLetters() {
        XCTAssertEqual(en("The human error was minimal"), "The human error was minimal")
        XCTAssertEqual(en("Her umbrella is here"), "Her umbrella is here")
    }

    func testOtherLanguagesPassThrough() {
        XCTAssertEqual(SpokenTextCleaner.clean("Selamat pagi, eh, apa kabar", languageCode: "id"), "Selamat pagi, eh, apa kabar")
    }
}

extension SpokenTextCleanerTests {
    func testOverlongKanjiDigitRunsAreLeftAloneInsteadOfOverflowing() {
        let run = String(repeating: "九", count: 40)
        XCTAssertEqual(ja(run + "年"), run + "年")
        let huge = "九千九百九十九万九千九百九十九万九千九百九十九万九千九百九十九万九千九百九十九"
        XCTAssertEqual(ja(huge + "円"), huge + "円")
    }
}
