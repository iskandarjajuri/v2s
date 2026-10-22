import Foundation

struct AppSettings: Codable {
    var selectedSourceID: String?
    var selectedSourceIDs: [String]
    var sourceLanguageOverrides: [String: String]
    var sourceOutputLanguageOverrides: [String: String]
    var inputLanguageID: String
    var outputLanguageID: String
    var interfaceLanguageID: String?
    var overlayStyle: OverlayStyle
    var subtitleMode: SubtitleMode
    var subtitleDisplayMode: SubtitleDisplayMode
    var glossary: [String: String]
    // 有効にすると Dock にアプリアイコンを常時表示する（.regular）。既定は menu-bar 専用（.accessory）。
    var showInDock: Bool
    var segmentation: SegmentationSettings
    var translationMode: TranslationQualityMode
    /// Strip fillers and stutters from the text sent to the translator (the subtitle keeps the original).
    var cleansSpokenText: Bool
    /// Names and terms corrected by sound before display and translation.
    var readingGlossary: [ReadingGlossaryEntry]
    /// Optional on-device rewrite of finished translations (Apple Intelligence). Off by default.
    var polishesTranslations: Bool

    static let `default` = AppSettings(
        selectedSourceID: nil,
        selectedSourceIDs: [],
        sourceLanguageOverrides: [:],
        sourceOutputLanguageOverrides: [:],
        inputLanguageID: "ja",
        outputLanguageID: "id",
        interfaceLanguageID: nil,
        overlayStyle: .default,
        subtitleMode: .balanced,
        subtitleDisplayMode: .both,
        glossary: [:],
        showInDock: false,
        segmentation: .default,
        translationMode: .progressive,
        cleansSpokenText: true,
        readingGlossary: [],
        polishesTranslations: false
    )

    // Custom decoder so existing settings files load cleanly as new fields are added.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        selectedSourceID = try? c.decodeIfPresent(String.self, forKey: .selectedSourceID)
        selectedSourceIDs = (try? c.decodeIfPresent([String].self, forKey: .selectedSourceIDs))
            ?? selectedSourceID.map { [$0] }
            ?? AppSettings.default.selectedSourceIDs
        sourceLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceLanguageOverrides))
            ?? AppSettings.default.sourceLanguageOverrides
        sourceOutputLanguageOverrides = (try? c.decodeIfPresent([String: String].self, forKey: .sourceOutputLanguageOverrides))
            ?? AppSettings.default.sourceOutputLanguageOverrides
        inputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .inputLanguageID))
            ?? AppSettings.default.inputLanguageID
        outputLanguageID = (try? c.decodeIfPresent(String.self, forKey: .outputLanguageID))
            ?? AppSettings.default.outputLanguageID
        interfaceLanguageID = try? c.decodeIfPresent(String.self, forKey: .interfaceLanguageID)
        overlayStyle = (try? c.decodeIfPresent(OverlayStyle.self, forKey: .overlayStyle))
            ?? AppSettings.default.overlayStyle
        subtitleMode = (try? c.decodeIfPresent(SubtitleMode.self, forKey: .subtitleMode))
            ?? AppSettings.default.subtitleMode
        subtitleDisplayMode = (try? c.decodeIfPresent(SubtitleDisplayMode.self, forKey: .subtitleDisplayMode))
            ?? AppSettings.default.subtitleDisplayMode
        glossary = (try? c.decodeIfPresent([String: String].self, forKey: .glossary))
            ?? AppSettings.default.glossary
        showInDock = (try? c.decodeIfPresent(Bool.self, forKey: .showInDock))
            ?? AppSettings.default.showInDock
        segmentation = (try? c.decodeIfPresent(SegmentationSettings.self, forKey: .segmentation))
            ?? AppSettings.default.segmentation
        translationMode = (try? c.decodeIfPresent(TranslationQualityMode.self, forKey: .translationMode))
            ?? AppSettings.default.translationMode
        cleansSpokenText = (try? c.decodeIfPresent(Bool.self, forKey: .cleansSpokenText))
            ?? AppSettings.default.cleansSpokenText
        readingGlossary = (try? c.decodeIfPresent([ReadingGlossaryEntry].self, forKey: .readingGlossary))
            ?? AppSettings.default.readingGlossary
        polishesTranslations = (try? c.decodeIfPresent(Bool.self, forKey: .polishesTranslations))
            ?? AppSettings.default.polishesTranslations
    }

    init(
        selectedSourceID: String?,
        selectedSourceIDs: [String] = [],
        sourceLanguageOverrides: [String: String] = [:],
        sourceOutputLanguageOverrides: [String: String] = [:],
        inputLanguageID: String,
        outputLanguageID: String,
        interfaceLanguageID: String?,
        overlayStyle: OverlayStyle,
        subtitleMode: SubtitleMode,
        subtitleDisplayMode: SubtitleDisplayMode,
        glossary: [String: String],
        showInDock: Bool = false,
        segmentation: SegmentationSettings = .default,
        translationMode: TranslationQualityMode = .progressive,
        cleansSpokenText: Bool = true,
        readingGlossary: [ReadingGlossaryEntry] = [],
        polishesTranslations: Bool = false
    ) {
        self.selectedSourceID = selectedSourceID
        self.selectedSourceIDs = selectedSourceIDs
        self.sourceLanguageOverrides = sourceLanguageOverrides
        self.sourceOutputLanguageOverrides = sourceOutputLanguageOverrides
        self.inputLanguageID  = inputLanguageID
        self.outputLanguageID = outputLanguageID
        self.interfaceLanguageID = interfaceLanguageID
        self.overlayStyle     = overlayStyle
        self.subtitleMode     = subtitleMode
        self.subtitleDisplayMode = subtitleDisplayMode
        self.glossary         = glossary
        self.showInDock       = showInDock
        self.segmentation     = segmentation
        self.translationMode  = translationMode
        self.cleansSpokenText = cleansSpokenText
        self.readingGlossary  = readingGlossary
        self.polishesTranslations = polishesTranslations
    }
}
