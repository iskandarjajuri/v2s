import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether the on-device language model can polish translations into a given language.
enum TranslationPolishAvailability: Equatable, Sendable {
    case available
    /// The model is present but does not officially support the target language (e.g. Indonesian).
    case unsupportedLanguage
    case modelUnavailable
    case systemTooOld
}

/// Decides whether a polished candidate may replace the translation that is already shown.
/// A language model can drift: add commentary, drop a clause or change a number. Anything that
/// looks like that is rejected and the existing translation stays.
enum TranslationPolishGuard {
    static func accepts(original: String, candidate: String) -> Bool {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false, trimmed != original else { return false }
        guard trimmed.contains("\n") == false || original.contains("\n") else { return false }

        let originalLength = Double(max(original.count, 1))
        let ratio = Double(trimmed.count) / originalLength
        guard ratio >= 0.6, ratio <= 1.7 else { return false }

        // Numbers must survive unchanged.
        guard digitRuns(in: original) == digitRuns(in: trimmed) else { return false }

        // Models like to announce themselves.
        let lowered = trimmed.lowercased()
        let chatter = ["here is", "here's", "sure,", "natural version", "rewritten", "berikut", "tentu,", "以下", "書き換え"]
        return chatter.contains(where: { lowered.hasPrefix($0) }) == false
    }

    private static func digitRuns(in text: String) -> [String] {
        // Thousands separators are formatting, not content ("100.000" vs "100,000").
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isNumber {
                current.append(character)
            } else if (character == "." || character == ",") && current.isEmpty == false {
                continue
            } else if current.isEmpty == false {
                runs.append(current)
                current = ""
            }
        }
        if current.isEmpty == false { runs.append(current) }
        return runs
    }
}

/// Optional second pass that rewrites a finished translation so it reads more naturally, using the
/// on-device language model. It never leaves the Mac, is skipped for unsupported languages, and is
/// bounded by a hard timeout; on any problem the caller simply keeps the translation it already has.
@MainActor
final class TranslationPolisher {
    static let timeoutSeconds = 2.5

    nonisolated static func availability(forTargetLanguageID languageID: String) -> TranslationPolishAvailability {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return .systemTooOld }
        let model = SystemLanguageModel.default
        guard case .available = model.availability else { return .modelUnavailable }
        let identifier = LanguageCatalog.translationLocaleIdentifier(for: languageID)
        return model.supportsLocale(Locale(identifier: identifier)) ? .available : .unsupportedLanguage
        #else
        return .systemTooOld
        #endif
    }

    /// Loads the model ahead of the first request so it does not eat the timeout.
    func prewarm() {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable else { return }
        makeSession().prewarm()
        #endif
    }

    /// Returns a polished translation, or nil when the model declined, timed out, was cancelled,
    /// or produced something the guard rejects.
    func polish(
        sourceText: String,
        translation: String,
        sourceLanguageName: String,
        targetLanguageName: String
    ) async -> String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), SystemLanguageModel.default.isAvailable else { return nil }
        let session = makeSession()
        let prompt = """
        Original (\(sourceLanguageName)): \(sourceText)
        Machine translation (\(targetLanguageName)): \(translation)
        Natural version:
        """

        let candidate: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                try? await session.respond(to: prompt).content
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(Self.timeoutSeconds * 1_000_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }

        guard Task.isCancelled == false, let candidate,
              TranslationPolishGuard.accepts(original: translation, candidate: candidate) else {
            return nil
        }
        return candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        #else
        return nil
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func makeSession() -> LanguageModelSession {
        // A fresh session per request keeps earlier captions from leaking into the next one.
        LanguageModelSession(instructions: """
        You polish machine translations. Rewrite the translation so it sounds natural and fluent in the \
        target language, the way a native speaker would say it in conversation. Keep the meaning, names and \
        numbers exactly. Output only the rewritten translation, nothing else.
        """)
    }
    #endif
}
