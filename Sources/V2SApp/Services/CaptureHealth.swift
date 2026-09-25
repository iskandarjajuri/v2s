import Darwin
import Foundation

/// 「画面とシステムオーディオの録音」権限の事前確認。
///
/// 公開 API は無い（拒否されていてもタップはエラーを出さず無音を返すだけ）。TCC.framework の
/// `TCCAccessPreflight` を dlopen で引く（insidegui/AudioCap と同じ方法）。見つからない OS では
/// `.unknown` を返し、呼び出し側は無音の続き方から推定する従来の経路にフォールバックする。
/// 事前確認はダイアログを出さない。
enum AudioCapturePermission: Equatable {
    case authorized
    case denied
    case unknown

    static func preflight() -> AudioCapturePermission {
        typealias PreflightFunction = @convention(c) (CFString, CFDictionary?) -> Int
        guard let handle = dlopen("/System/Library/PrivateFrameworks/TCC.framework/Versions/A/TCC", RTLD_NOW),
              let symbol = dlsym(handle, "TCCAccessPreflight") else {
            return .unknown
        }
        let preflight = unsafeBitCast(symbol, to: PreflightFunction.self)
        switch preflight("kTCCServiceAudioCapture" as CFString, nil) {
        case 0:
            return .authorized
        case 1:
            return .denied
        default:
            return .unknown
        }
    }
}

/// キャプチャ経路の健全性。`LiveTranscriptionSession` の watchdog が 2 秒ごとに評価する。
///
/// 前提として実機で確認した Core Audio の挙動：プロセスタップを載せた集約デバイスの IOProc は、
/// タップ対象のプロセスが**音を出していない間はまったく呼ばれない**（Chrome の AudioService に
/// タップし、無音時 0 コール／再生時 ~93 コール/秒）。したがって「バッファが来ない」だけでは
/// 異常と言えない。会議前のロビーや、誰も話していない Meet の待機画面はこの状態になる。
/// 対象が音を出しているか（`kAudioProcessPropertyIsRunningOutput`）を先に見てから判定する。
enum CaptureHealthVerdict: Equatable {
    /// 正常。
    case healthy
    /// 対象アプリが音を出していない。異常ではない（UI では「音声待ち」と表示する）。
    case sourceIdle
    /// 対象アプリは音を出しているのに、IOProc からバッファが届かない
    /// （集約デバイスやタップが古くなった等）。
    case audioStarved
    /// 対象アプリは音を出しているのに、届くバッファがデジタル無音のまま
    /// （タップ対象のプロセス集合が古い、または「システムオーディオ録音」権限が無い）。
    case captureSilent
    /// 音は来ているのに ASR の結果が途絶えた。
    case pipelineStalled
}

/// watchdog が判定の結果として取る行動。
enum CaptureRecoveryAction: Equatable {
    case none
    /// タップと集約デバイスだけを作り直す（認識器はそのまま）。安価なので積極的に使う。
    case rebuildCapture
    /// セッションを丸ごと作り直す（ASR の詰まり用）。
    case restartSession
    /// 何度作り直しても無音。権限不足が濃厚なので、再試行をやめてユーザーに知らせる。
    case reportPermissionProblem
}

/// UI に出すキャプチャ状態。
enum CaptureHealthStatus: Equatable {
    case starting
    case hearingAudio
    case waitingForSourceAudio
    case reconnecting
    case permissionProblemSuspected
}

enum CaptureHealth {
    struct Timing: Equatable {
        var audioStarvationTimeout: TimeInterval = 6
        var silentCaptureTimeout: TimeInterval = 20
        var resultTimeout: TimeInterval = 10
        var speechRecency: TimeInterval = 3
    }

    /// 権限不足と判断するまでに試す作り直しの回数。
    static let silentRebuildsBeforePermissionReport = 2

    /// watchdog の判定本体。副作用を持たない純関数にしてあるのでそのままテストできる。
    ///
    /// 判定順序に意味がある。まず「対象が音を出しているか」、次に「音が届いているか」、次に
    /// 「届いた音に中身があるか」、最後に ASR の詰まりを見る。逆順にすると、音が来ていない状態を
    /// ASR の問題と誤診する。
    ///
    /// - Parameters:
    ///   - captureBuildTime: タップを（作り直しを含めて）最後に組んだ時刻。起動直後と作り直し直後の猶予に使う。
    ///   - lastNonSilentAudioTime: 最後にデジタル無音でないバッファを受け取った時刻。
    ///   - speechResumedTime: 静寂のあと発話が再開した時刻。ASR の猶予はここから数える。
    ///     「最後の結果から」数えると、長い静寂のあと話し始めた瞬間に（認識器が最初の結果を
    ///     返す前に）詰まりと誤判定し、会議の最初の一文ごとにセッションを作り直してしまう。
    ///   - sourceIsRenderingAudio: タップ対象のいずれかのプロセスが出力中か。マイク入力では常に true。
    static func verdict(
        now: Date,
        captureBuildTime: Date,
        lastAudioBufferTime: Date,
        lastNonSilentAudioTime: Date,
        lastRecognitionResultTime: Date,
        lastSpeechActivityTime: Date,
        speechResumedTime: Date = .distantPast,
        sourceIsRenderingAudio: Bool,
        timing: Timing = Timing()
    ) -> CaptureHealthVerdict {
        // 0) ASR の詰まりは音の有無と独立に起こる。発話が直近にある＝音は来ているので先に見てよい。
        let awaitingResultsSince = max(lastRecognitionResultTime, speechResumedTime)
        let noResults = now.timeIntervalSince(awaitingResultsSince) > timing.resultTimeout
        let speechPresent = now.timeIntervalSince(lastSpeechActivityTime) < timing.speechRecency
        if noResults, speechPresent {
            return .pipelineStalled
        }

        // 1) 対象が音を出していなければ、バッファが来ないのも無音なのも正常。
        guard sourceIsRenderingAudio else {
            return .sourceIdle
        }

        let sinceBuild = now.timeIntervalSince(captureBuildTime)

        // 2) 音を出しているのにバッファが来ない。
        if sinceBuild > timing.audioStarvationTimeout,
           now.timeIntervalSince(lastAudioBufferTime) > timing.audioStarvationTimeout {
            return .audioStarved
        }

        // 3) 音を出しているのに、作り直し以降（または最後の実音声以降）ずっとデジタル無音。
        //    captureBuildTime を起点に含めるので、作り直すたびに猶予がリセットされ、
        //    静かな会議でも作り直しは silentCaptureTimeout に 1 回までに抑えられる。
        let silentSince = max(captureBuildTime, lastNonSilentAudioTime)
        if now.timeIntervalSince(silentSince) > timing.silentCaptureTimeout {
            return .captureSilent
        }

        return .healthy
    }

    /// 判定から行動を決める。
    ///
    /// - Parameters:
    ///   - canRebuildCaptureInPlace: アプリ音声（プロセスタップ）なら true。マイクは作り直し経路を持たない。
    ///   - hasEverReceivedNonSilentAudio: このセッションで一度でも実音声を受け取ったか。
    ///   - consecutiveSilentRebuilds: `captureSilent` による作り直しが実音声なしで続いた回数。
    ///   - permissionProblemReported: すでに権限の問題を報告済みか（重複報告と再試行ループを防ぐ）。
    ///   - permission: 権限の事前確認結果。分かっていれば推定より優先する。
    static func recoveryAction(
        for verdict: CaptureHealthVerdict,
        canRebuildCaptureInPlace: Bool,
        hasEverReceivedNonSilentAudio: Bool,
        consecutiveSilentRebuilds: Int,
        permissionProblemReported: Bool,
        permission: AudioCapturePermission = .unknown
    ) -> CaptureRecoveryAction {
        switch verdict {
        case .healthy, .sourceIdle:
            return .none
        case .pipelineStalled:
            return .restartSession
        case .audioStarved:
            return canRebuildCaptureInPlace ? .rebuildCapture : .restartSession
        case .captureSilent:
            guard canRebuildCaptureInPlace else {
                // マイクの無音は「誰も話していない」が普通。作り直しても意味がない。
                return .none
            }
            switch permission {
            case .denied:
                // 確実に権限が無い。作り直しても無音なので、すぐに知らせる。
                return permissionProblemReported ? .none : .reportPermissionProblem
            case .authorized:
                // 権限はある。無音は本当に無音（会議のロビー、全員ミュート等）であることが多い。
                // 経路が古くなった可能性に備えて作り直しは静寂 1 回につき 1 度だけにし、
                // 権限の警告は決して出さない（誤警告で不安にさせない）。
                return consecutiveSilentRebuilds >= 1 ? .none : .rebuildCapture
            case .unknown:
                if hasEverReceivedNonSilentAudio == false,
                   consecutiveSilentRebuilds >= silentRebuildsBeforePermissionReport {
                    return permissionProblemReported ? .none : .reportPermissionProblem
                }
                return .rebuildCapture
            }
        }
    }

    /// UI 向けの状態。
    static func status(
        for verdict: CaptureHealthVerdict,
        hasEverReceivedNonSilentAudio: Bool,
        permissionProblemReported: Bool,
        isRebuilding: Bool
    ) -> CaptureHealthStatus {
        if permissionProblemReported {
            return .permissionProblemSuspected
        }
        if isRebuilding {
            return .reconnecting
        }
        switch verdict {
        case .sourceIdle, .captureSilent:
            // 出力中でも中身が無音なら、ユーザーから見れば「アプリが黙っている」。
            // Chrome は一時停止中も AudioService が無音を出し続けるので、ここを「再接続中」に
            // すると静かなロビーで永遠に再接続表示のままになる。実際の作り直しは isRebuilding で出す。
            return .waitingForSourceAudio
        case .healthy, .pipelineStalled:
            return hasEverReceivedNonSilentAudio ? .hearingAudio : .starting
        case .audioStarved:
            return .reconnecting
        }
    }

    /// 0...1 のメーター値。RMS を dBFS にして -60 dB〜0 dB を線形に写す。
    static func meterLevel(rms: Float) -> Float {
        guard rms > 0 else {
            return 0
        }
        let decibels = 20 * log10(rms)
        return min(max((decibels + 60) / 60, 0), 1)
    }
}
