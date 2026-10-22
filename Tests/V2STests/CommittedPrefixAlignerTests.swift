import XCTest
@testable import v2s

final class CommittedPrefixAlignerTests: XCTestCase {
    func testStripsAnExactlyMatchingPrefix() {
        let rest = CommittedPrefixAligner.remainder(
            of: "おはようございます。今日もよろしくお願いします。",
            afterCommitted: "おはようございます。"
        )
        XCTAssertEqual(rest, "今日もよろしくお願いします。")
    }

    func testToleratesKanjiToKanaRewriteInsideTheCommittedPart() {
        let committed = "今日は朝から会議があって、その後すぐに新しいプロジェクトの打ち合わせに行かなければならないので、昼ご飯を食べる時間がありませんでした。"
        let full = "今日は朝から会議があって、その後すぐに新しいプロジェクトの打ち合わせに行かなければならないので、昼ごはんを食べる時間がありませんでした。来週の月曜日までに資料を準備しておいてください。"
        XCTAssertEqual(
            CommittedPrefixAligner.remainder(of: full, afterCommitted: committed),
            "来週の月曜日までに資料を準備しておいてください。"
        )
    }

    func testToleratesNumberFormattingRewriteInEnglish() {
        let committed = "Mr. Smith said the price went up by 3.5 percent last quarter."
        let full = "Mr. Smith said the price went up by 3.5% last quarter. We expect it to rise again."
        XCTAssertEqual(
            CommittedPrefixAligner.remainder(of: full, afterCommitted: committed),
            "We expect it to rise again."
        )
    }

    func testReturnsEmptyWhenNothingFollowsTheCommittedPart() {
        XCTAssertEqual(
            CommittedPrefixAligner.remainder(of: "会議は終わりました。", afterCommitted: "会議は終わりました"),
            ""
        )
    }

    func testRejectsTextThatDoesNotLineUp() {
        XCTAssertNil(CommittedPrefixAligner.remainder(
            of: "まったく別の話題について話しています。",
            afterCommitted: "今日は朝から会議がありました。"
        ))
    }

    func testRejectsTooShortACommittedPrefixToTrust() {
        XCTAssertNil(CommittedPrefixAligner.remainder(of: "はい。次です。", afterCommitted: "はい"))
    }

    func testLongHistoryWithARewriteNearTheEndStillAligns() {
        let history = (0..<120).map { "これは\($0)番目の文章で内容は昼ご飯のことです。" }.joined()
        let rewritten = history.replacingOccurrences(of: "昼ご飯", with: "昼ごはん")
        let rest = CommittedPrefixAligner.remainder(
            of: rewritten + "新しい文章が始まりました。",
            afterCommitted: history
        )
        XCTAssertEqual(rest, "新しい文章が始まりました。")
    }

    func testVeryLongHistoryStaysCheap() {
        let history = String(repeating: "あいうえおかきくけこさしすせそ。", count: 1_000)
        let full = history + "つぎの文です。"
        let committed = history.replacingOccurrences(of: "あいうえお", with: "あいうえを")
        measure {
            XCTAssertEqual(CommittedPrefixAligner.remainder(of: full, afterCommitted: committed), "つぎの文です。")
        }
    }
}
