import XCTest
@testable import v2s

/// watchdog の判定ロジックのテスト。
///
/// 回帰の対象は 2 つ。
/// 1. 「音がまったく来ていないのに watchdog が沈黙する」死角（旧実装は VAD の発話検出を
///    and 条件にしていたため、音が 1 バッファも来ない障害を報告できなかった）。
/// 2. その修正が生んだ逆の問題。IOProc は対象プロセスが音を出していない間は呼ばれないので、
///    「バッファが来ない＝異常」とすると、会議前のロビーなど対象が黙っているだけで
///    12 秒ごとにセッションを作り直し続けてしまう。
final class CaptureHealthVerdictTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let never: TimeInterval = 100_000

    private func verdict(
        elapsed: TimeInterval,
        sinceAudioBuffer: TimeInterval,
        sinceNonSilentAudio: TimeInterval,
        sinceResult: TimeInterval,
        sinceSpeech: TimeInterval,
        rendering: Bool = true
    ) -> CaptureHealthVerdict {
        let now = start.addingTimeInterval(elapsed)
        return CaptureHealth.verdict(
            now: now,
            captureBuildTime: start,
            lastAudioBufferTime: now.addingTimeInterval(-sinceAudioBuffer),
            lastNonSilentAudioTime: now.addingTimeInterval(-sinceNonSilentAudio),
            lastRecognitionResultTime: now.addingTimeInterval(-sinceResult),
            lastSpeechActivityTime: now.addingTimeInterval(-sinceSpeech),
            sourceIsRenderingAudio: rendering
        )
    }

    // MARK: - 音が来ない障害を検出できること

    /// 対象は音を出しているのに IOProc が呼ばれない（集約デバイスが古くなった等）。
    func testNoBuffersWhileSourceRendersIsStarvation() {
        XCTAssertEqual(
            verdict(elapsed: 30, sinceAudioBuffer: 30, sinceNonSilentAudio: never, sinceResult: 30, sinceSpeech: never),
            .audioStarved
        )
    }

    /// バッファは届くが中身がずっとデジタル無音（権限なし・古いプロセス集合）。
    func testSilentBuffersWhileSourceRendersIsCaptureSilent() {
        XCTAssertEqual(
            verdict(elapsed: 30, sinceAudioBuffer: 0.1, sinceNonSilentAudio: never, sinceResult: 30, sinceSpeech: never),
            .captureSilent
        )
    }

    /// 会議の途中で（Bluetooth の A2DP→HFP 切り替え等で）無音になった場合も拾えること。
    /// 旧実装は「一度でも実音声があれば正常」としていたため、ここを見逃していた。
    func testMidMeetingDeadAirIsDetected() {
        XCTAssertEqual(
            verdict(elapsed: 600, sinceAudioBuffer: 0.1, sinceNonSilentAudio: 25, sinceResult: 25, sinceSpeech: 25),
            .captureSilent
        )
    }

    // MARK: - 誤検出しないこと

    /// 回帰 2 の本丸。対象が音を出していなければ、バッファが来なくても異常ではない。
    func testSourceNotRenderingIsIdleNotStarved() {
        XCTAssertEqual(
            verdict(elapsed: 120, sinceAudioBuffer: 120, sinceNonSilentAudio: never, sinceResult: 120, sinceSpeech: never, rendering: false),
            .sourceIdle
        )
    }

    func testStartupGraceDoesNotReportStarvation() {
        XCTAssertEqual(
            verdict(elapsed: 3, sinceAudioBuffer: 3, sinceNonSilentAudio: never, sinceResult: 3, sinceSpeech: never),
            .healthy
        )
    }

    /// 作り直し直後にも猶予が与えられること（captureBuildTime 起点）。
    func testRebuildResetsSilenceGrace() {
        let now = start.addingTimeInterval(600)
        let rebuiltAt = now.addingTimeInterval(-5)
        XCTAssertEqual(
            CaptureHealth.verdict(
                now: now,
                captureBuildTime: rebuiltAt,
                lastAudioBufferTime: now,
                lastNonSilentAudioTime: .distantPast,
                lastRecognitionResultTime: now.addingTimeInterval(-300),
                lastSpeechActivityTime: .distantPast,
                sourceIsRenderingAudio: true
            ),
            .healthy
        )
    }

    func testActiveCaptureIsHealthy() {
        XCTAssertEqual(
            verdict(elapsed: 120, sinceAudioBuffer: 0.05, sinceNonSilentAudio: 0.05, sinceResult: 1, sinceSpeech: 0.5),
            .healthy
        )
    }

    /// 回帰 3。長い静寂のあと話し始めた直後は、認識器が最初の結果を返すまで待つこと。
    /// 旧実装は最後の結果（1 分前）から数えていたため、話し始めた瞬間に詰まり扱いで
    /// セッションを作り直し、会議の最初の一文を落としていた（実機ログで確認）。
    func testSpeechResumingAfterLongSilenceIsNotAStall() {
        let now = start.addingTimeInterval(120)
        XCTAssertEqual(
            CaptureHealth.verdict(
                now: now,
                captureBuildTime: start,
                lastAudioBufferTime: now,
                lastNonSilentAudioTime: now,
                lastRecognitionResultTime: now.addingTimeInterval(-60),
                lastSpeechActivityTime: now,
                speechResumedTime: now.addingTimeInterval(-2),
                sourceIsRenderingAudio: true
            ),
            .healthy
        )
    }

    func testSpeechWithoutResultsLongAfterResumingIsAStall() {
        let now = start.addingTimeInterval(120)
        XCTAssertEqual(
            CaptureHealth.verdict(
                now: now,
                captureBuildTime: start,
                lastAudioBufferTime: now,
                lastNonSilentAudioTime: now,
                lastRecognitionResultTime: now.addingTimeInterval(-60),
                lastSpeechActivityTime: now,
                speechResumedTime: now.addingTimeInterval(-15),
                sourceIsRenderingAudio: true
            ),
            .pipelineStalled
        )
    }

    // MARK: - 既存の検出を壊していないこと

    func testPipelineStallIsStillDetectedWhenSpeechPresentButNoResults() {
        XCTAssertEqual(
            verdict(elapsed: 60, sinceAudioBuffer: 0.1, sinceNonSilentAudio: 0.1, sinceResult: 15, sinceSpeech: 1),
            .pipelineStalled
        )
    }
}

final class CaptureRecoveryPolicyTests: XCTestCase {
    private func action(
        _ verdict: CaptureHealthVerdict,
        inPlace: Bool = true,
        everHeard: Bool = false,
        silentRebuilds: Int = 0,
        reported: Bool = false,
        permission: AudioCapturePermission = .unknown
    ) -> CaptureRecoveryAction {
        CaptureHealth.recoveryAction(
            for: verdict,
            canRebuildCaptureInPlace: inPlace,
            hasEverReceivedNonSilentAudio: everHeard,
            consecutiveSilentRebuilds: silentRebuilds,
            permissionProblemReported: reported,
            permission: permission
        )
    }

    /// 実機で観測：Chrome は一時停止中も AudioService が無音を出力し続ける（IsRunningOutput = 1）。
    /// 権限があると分かっているなら、この無音で権限の警告を出してはならない。作り直しも 1 度きり。
    func testAuthorizedSilenceRebuildsOnceAndNeverBlamesPermission() {
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 0, permission: .authorized), .rebuildCapture)
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 1, permission: .authorized), .none)
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 7, permission: .authorized), .none)
    }

    func testDeniedPermissionIsReportedImmediately() {
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 0, permission: .denied), .reportPermissionProblem)
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 0, reported: true, permission: .denied), .none)
    }

    func testIdleAndHealthyDoNothing() {
        XCTAssertEqual(action(.healthy), .none)
        XCTAssertEqual(action(.sourceIdle), .none)
    }

    /// 音の問題は認識器を捨てずにタップだけ作り直す。
    func testCaptureProblemsRebuildOnlyTheTap() {
        XCTAssertEqual(action(.audioStarved), .rebuildCapture)
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 1), .rebuildCapture)
    }

    func testPipelineStallRestartsSession() {
        XCTAssertEqual(action(.pipelineStalled), .restartSession)
    }

    /// 権限が無いと何度作り直しても無音。無限ループにせず、一度だけユーザーに知らせる。
    func testRepeatedSilenceWithoutAnyAudioReportsPermissionOnce() {
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 2), .reportPermissionProblem)
        XCTAssertEqual(action(.captureSilent, silentRebuilds: 5, reported: true), .none)
    }

    /// 一度でも音が聞こえていれば権限はある。途中の無音は作り直しで直す。
    func testSilenceAfterWorkingAudioNeverBlamesPermission() {
        XCTAssertEqual(action(.captureSilent, everHeard: true, silentRebuilds: 9), .rebuildCapture)
    }

    func testMicrophoneHasNoInPlaceRebuild() {
        XCTAssertEqual(action(.audioStarved, inPlace: false), .restartSession)
        XCTAssertEqual(action(.captureSilent, inPlace: false), .none)
    }
}

final class CaptureHealthStatusTests: XCTestCase {
    func testStatusMapping() {
        XCTAssertEqual(
            CaptureHealth.status(for: .sourceIdle, hasEverReceivedNonSilentAudio: false, permissionProblemReported: false, isRebuilding: false),
            .waitingForSourceAudio
        )
        XCTAssertEqual(
            CaptureHealth.status(for: .healthy, hasEverReceivedNonSilentAudio: true, permissionProblemReported: false, isRebuilding: false),
            .hearingAudio
        )
        XCTAssertEqual(
            CaptureHealth.status(for: .healthy, hasEverReceivedNonSilentAudio: false, permissionProblemReported: false, isRebuilding: false),
            .starting
        )
        XCTAssertEqual(
            CaptureHealth.status(for: .captureSilent, hasEverReceivedNonSilentAudio: false, permissionProblemReported: true, isRebuilding: false),
            .permissionProblemSuspected
        )
        XCTAssertEqual(
            CaptureHealth.status(for: .healthy, hasEverReceivedNonSilentAudio: true, permissionProblemReported: false, isRebuilding: true),
            .reconnecting
        )
    }

    func testMeterLevel() {
        XCTAssertEqual(CaptureHealth.meterLevel(rms: 0), 0)
        XCTAssertEqual(CaptureHealth.meterLevel(rms: 1), 1, accuracy: 0.0001)
        XCTAssertEqual(CaptureHealth.meterLevel(rms: 0.001), 0, accuracy: 0.0001) // -60 dB
        XCTAssertEqual(CaptureHealth.meterLevel(rms: 0.0316), 0.5, accuracy: 0.01) // -30 dB
    }
}

final class SourceOrderingTests: XCTestCase {
    private func app(_ name: String, _ bundleIdentifier: String) -> InputSource {
        InputSource(id: "app:\(bundleIdentifier)", name: name, detail: bundleIdentifier, category: .application)
    }

    func testAppsPlayingAudioThroughHelpersComeFirst() {
        let ordered = SourceCatalogService.orderedApplications(
            [app("Finder", "com.apple.finder"), app("Google Chrome", "com.google.Chrome"), app("Music", "com.apple.Music")],
            playingBundleIdentifiers: ["com.google.Chrome.helper"]
        )
        XCTAssertEqual(ordered.map(\.name), ["Google Chrome", "Finder", "Music"])
    }

    func testSafariCountsAsPlayingWhenWebKitGPUPlays() {
        let ordered = SourceCatalogService.orderedApplications(
            [app("Notes", "com.apple.Notes"), app("Safari", "com.apple.Safari")],
            playingBundleIdentifiers: ["com.apple.WebKit.GPU"]
        )
        XCTAssertEqual(ordered.first?.name, "Safari")
    }

    /// 前方一致は「.」区切りでだけ効くこと（com.google.ChromeX を Chrome と取り違えない）。
    func testPrefixMatchRequiresDotBoundary() {
        let ordered = SourceCatalogService.orderedApplications(
            [app("Alpha", "com.alpha"), app("Chrome", "com.google.Chrome")],
            playingBundleIdentifiers: ["com.google.ChromeCanary"]
        )
        XCTAssertEqual(ordered.map(\.name), ["Alpha", "Chrome"])
    }
}

final class CombinedCaptureHealthTests: XCTestCase {
    @MainActor
    func testAnyHearingSourceWins() {
        XCTAssertEqual(AppModel.combinedCaptureHealth([.permissionProblemSuspected, .hearingAudio]), .hearingAudio)
        XCTAssertEqual(AppModel.combinedCaptureHealth([.waitingForSourceAudio, .permissionProblemSuspected]), .permissionProblemSuspected)
        XCTAssertNil(AppModel.combinedCaptureHealth([]))
    }
}
