import XCTest
@testable import v2s

/// watchdog の判定ロジックのテスト。
///
/// 回帰の対象は「音がまったく来ていないのに watchdog が沈黙する」という死角。
/// 旧実装は `speechPresent`（VAD が直近に発話を検出したか）を **and 条件**にしていたため、
/// 音が 1 バッファも来ない障害では VAD が一度も走らず、`speechPresent` が永久に false になり、
/// 異常を報告できなかった。UI は開始時のプレースホルダ（「音声待ち」）のまま固まる。
final class CaptureHealthVerdictTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)

    private func verdict(
        elapsed: TimeInterval,
        sinceAudioBuffer: TimeInterval,
        sinceResult: TimeInterval,
        sinceSpeech: TimeInterval,
        hasEverReceivedNonSilentAudio: Bool = true
    ) -> CaptureHealthVerdict {
        let now = start.addingTimeInterval(elapsed)
        return LiveTranscriptionSession.captureHealthVerdict(
            now: now,
            captureStartTime: start,
            lastAudioBufferTime: now.addingTimeInterval(-sinceAudioBuffer),
            lastRecognitionResultTime: now.addingTimeInterval(-sinceResult),
            lastSpeechActivityTime: now.addingTimeInterval(-sinceSpeech),
            hasEverReceivedNonSilentAudio: hasEverReceivedNonSilentAudio,
            audioStarvationTimeout: 6,
            silentCaptureTimeout: 25,
            resultTimeout: 10,
            speechRecency: 3
        )
    }

    // MARK: - 回帰テスト：音が来ない障害を検出できること

    /// 本丸。Bluetooth ヘッドセットの切り替え等で出力デバイスが変わり、集約デバイスの
    /// sub-device が無効になると IOProc が呼ばれなくなる。発話は一度も検出されない
    /// （＝ sinceSpeech は無限大相当）が、これは異常として報告されなければならない。
    func testNoAudioBuffersIsDetectedEvenThoughVADNeverFired() {
        XCTAssertEqual(
            verdict(
                elapsed: 30,
                sinceAudioBuffer: 30,
                sinceResult: 30,
                sinceSpeech: 10_000,          // VAD は一度も発火していない
                hasEverReceivedNonSilentAudio: false
            ),
            .audioStarved
        )
    }

    /// バッファは届いているが中身がデジタル無音のまま（開始時に音を出していない
    /// プロセス集合を掴んでいた場合）。こちらも報告されなければならない。
    func testSilentCaptureIsDetectedWhenBuffersArriveButNeverContainAudio() {
        XCTAssertEqual(
            verdict(
                elapsed: 30,
                sinceAudioBuffer: 0.1,        // IOProc は生きている
                sinceResult: 30,
                sinceSpeech: 10_000,
                hasEverReceivedNonSilentAudio: false
            ),
            .captureSilent
        )
    }

    // MARK: - 既存の検出を壊していないこと

    func testPipelineStallIsStillDetectedWhenSpeechPresentButNoResults() {
        XCTAssertEqual(
            verdict(elapsed: 60, sinceAudioBuffer: 0.1, sinceResult: 15, sinceSpeech: 1),
            .pipelineStalled
        )
    }

    // MARK: - 誤検出しないこと

    /// 起動直後は猶予を与える。まだ音が来ていなくても異常にしない。
    func testStartupGraceDoesNotReportStarvation() {
        XCTAssertEqual(
            verdict(
                elapsed: 3,
                sinceAudioBuffer: 3,
                sinceResult: 3,
                sinceSpeech: 10_000,
                hasEverReceivedNonSilentAudio: false
            ),
            .healthy
        )
    }

    /// 一度でも実音声が入っていれば、その後の静寂（会議中の間）は正常。
    /// ここを誤検出すると、黙っているだけで延々と再接続してしまう。
    func testSilenceAfterWorkingAudioIsHealthy() {
        XCTAssertEqual(
            verdict(
                elapsed: 600,
                sinceAudioBuffer: 0.1,
                sinceResult: 300,
                sinceSpeech: 300,
                hasEverReceivedNonSilentAudio: true
            ),
            .healthy
        )
    }

    /// 音も結果も来ている通常状態。
    func testActiveCaptureIsHealthy() {
        XCTAssertEqual(
            verdict(elapsed: 120, sinceAudioBuffer: 0.05, sinceResult: 1, sinceSpeech: 0.5),
            .healthy
        )
    }

    /// 判定順序の確認：音が途絶えているときは ASR の問題ではなく音の問題と診断する。
    func testStarvationTakesPrecedenceOverPipelineStall() {
        XCTAssertEqual(
            verdict(elapsed: 60, sinceAudioBuffer: 30, sinceResult: 30, sinceSpeech: 1),
            .audioStarved
        )
    }
}
