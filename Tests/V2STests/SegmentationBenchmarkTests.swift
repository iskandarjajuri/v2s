import XCTest
@testable import v2s

/// Offline benchmark: replays the `say`-generated corpus (see ~/Projects/v2s-work/bench)
/// through the real `LiveTranscriptionSession` and records timestamped events as JSON.
/// Skipped unless `V2S_BENCH_OUT` is set (pass it as `TEST_RUNNER_V2S_BENCH_OUT`), because
/// it needs installed speech assets and runs in real time.
final class SegmentationBenchmarkTests: XCTestCase {
    private struct Event: Codable {
        let t: Double
        let kind: String
        let text: String
        let stablePrefix: Int?
        let promotionID: String?
    }

    private struct Run: Codable {
        let corpus: String
        let events: [Event]
    }

    @MainActor
    func testReplayCorpus() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let outPath = env["V2S_BENCH_OUT"] else {
            throw XCTSkip("V2S_BENCH_OUT not set")
        }
        let audioDir = URL(fileURLWithPath: env["V2S_BENCH_AUDIO"] ?? NSString(string: "~/Projects/v2s-work/bench/audio").expandingTildeInPath)
        let names = (env["V2S_BENCH_CORPUS"] ?? "ja_fast,ja_normal,en_fast").split(separator: ",").map(String.init)
        let metaData = try Data(contentsOf: audioDir.appendingPathComponent("meta.json"))
        let meta = try JSONSerialization.jsonObject(with: metaData) as? [String: [String: Any]] ?? [:]

        var segmentation = SegmentationSettings.default
        if env["V2S_BENCH_SEG"] == "off" { segmentation.isEnabled = false }
        if let value = env["V2S_BENCH_MAXSEC"].flatMap(Double.init) { segmentation.maxContinuousSpeechSeconds = value }
        if let value = env["V2S_BENCH_STABLE_MS"].flatMap(Int.init) { segmentation.stableLeadingMs = value }

        var runs: [Run] = []
        for name in names {
            guard let locale = meta[name]?["locale"] as? String else {
                XCTFail("corpus \(name) missing from meta.json")
                continue
            }
            let session = LiveTranscriptionSession()
            let start = Date()
            let lock = NSLock()
            var events: [Event] = []
            func record(_ kind: String, _ text: String, stable: Int? = nil, promotion: UUID? = nil) {
                lock.lock()
                events.append(Event(
                    t: Date().timeIntervalSince(start),
                    kind: kind,
                    text: text,
                    stablePrefix: stable,
                    promotionID: promotion?.uuidString
                ))
                lock.unlock()
            }

            try await session.replayForTesting(
                audioFile: audioDir.appendingPathComponent("\(name).wav"),
                localeIdentifier: locale,
                segmentation: segmentation,
                transcriptHandler: { record("commit", $0.text, promotion: $0.promotionSegmentID) },
                partialHandler: { draft in
                    if let draft {
                        record("partial", draft.sourceText, stable: draft.stablePrefixLength, promotion: draft.segmentId)
                    } else {
                        record("clear", "")
                    }
                }
            )
            lock.lock()
            runs.append(Run(corpus: name, events: events))
            lock.unlock()
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(runs).write(to: URL(fileURLWithPath: outPath))
    }
}
