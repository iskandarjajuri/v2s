import Foundation
import XCTest
@testable import v2s

final class AppSettingsTests: XCTestCase {
    func testLegacySingleSourceSettingsDecodeIntoMultiSourceFields() throws {
        let json = """
        {
          "selectedSourceID": "mic-1",
          "inputLanguageID": "en",
          "outputLanguageID": "ja",
          "overlayStyle": {
            "translatedFontSize": 20,
            "sourceFontSize": 16,
            "backgroundOpacity": 0.7,
            "subtitleColor": { "kind": "defaultSubtitle" },
            "textColor": { "kind": "defaultText" },
            "backgroundColor": { "kind": "defaultBackground" },
            "showsTextOutline": true,
            "textOutlineColor": { "kind": "defaultTextOutline" },
            "attachToSource": true,
            "translatedFirst": true
          },
          "subtitleMode": "balanced",
          "subtitleDisplayMode": "both",
          "glossary": {}
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.selectedSourceID, "mic-1")
        XCTAssertEqual(settings.selectedSourceIDs, ["mic-1"])
        XCTAssertTrue(settings.sourceLanguageOverrides.isEmpty)
        XCTAssertTrue(settings.sourceOutputLanguageOverrides.isEmpty)
    }

    func testSettingsWrittenBeforeNaturalFastFeaturesLoadWithDefaults() throws {
        let json = """
        {
          "inputLanguageID": "ja",
          "outputLanguageID": "id",
          "overlayStyle": {
            "topInset": 12, "widthRatio": 0.82, "minWidth": 720, "maxWidth": 1440,
            "backgroundOpacity": 0.32, "translatedFontSize": 24, "sourceFontSize": 18, "clickThrough": true
          },
          "subtitleMode": "follow",
          "subtitleDisplayMode": "both",
          "glossary": { "CEO": "Direktur" },
          "showInDock": true
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertEqual(settings.subtitleMode, .follow)
        XCTAssertEqual(settings.glossary, ["CEO": "Direktur"])
        XCTAssertTrue(settings.showInDock)
        XCTAssertEqual(settings.segmentation, .default)
        XCTAssertEqual(settings.translationMode, .progressive)
        XCTAssertTrue(settings.cleansSpokenText)
        XCTAssertTrue(settings.readingGlossary.isEmpty)
    }

    func testNaturalFastSettingsRoundTrip() throws {
        var settings = AppSettings.default
        settings.segmentation = SegmentationSettings(isEnabled: false, maxContinuousSpeechSeconds: 9, stableLeadingMs: 300, cutAtJapaneseClauseEndings: false)
        settings.translationMode = .fastOnly
        settings.cleansSpokenText = false
        settings.readingGlossary = [ReadingGlossaryEntry(term: "石橋誠", reading: "いしばしまこと", language: "ja")]

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        XCTAssertEqual(decoded.segmentation, settings.segmentation)
        XCTAssertEqual(decoded.translationMode, .fastOnly)
        XCTAssertFalse(decoded.cleansSpokenText)
        XCTAssertEqual(decoded.readingGlossary, settings.readingGlossary)
    }

    func testCorruptNewFieldsFallBackToDefaultsInsteadOfFailingTheWholeFile() throws {
        let json = """
        {
          "inputLanguageID": "en", "outputLanguageID": "ja",
          "overlayStyle": { "topInset": 12, "widthRatio": 0.8, "minWidth": 700, "maxWidth": 1400,
            "backgroundOpacity": 0.3, "translatedFontSize": 24, "sourceFontSize": 18, "clickThrough": true },
          "subtitleMode": "balanced", "subtitleDisplayMode": "both", "glossary": {},
          "translationMode": "warp-speed",
          "segmentation": "oops"
        }
        """
        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
        XCTAssertEqual(settings.translationMode, .progressive)
        XCTAssertEqual(settings.segmentation, .default)
    }

    func testMultiSourceSettingsRoundTripPreservesOverrides() throws {
        let settings = AppSettings(
            selectedSourceID: "mic-1",
            selectedSourceIDs: ["mic-1", "app-1"],
            sourceLanguageOverrides: ["app-1": "fr"],
            sourceOutputLanguageOverrides: ["mic-1": "zh-Hans", "app-1": "de"],
            inputLanguageID: "en",
            outputLanguageID: "ja",
            interfaceLanguageID: "en",
            overlayStyle: .default,
            subtitleMode: .balanced,
            subtitleDisplayMode: .both,
            glossary: ["CEO": "Chief Executive Officer"]
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.selectedSourceID, "mic-1")
        XCTAssertEqual(decoded.selectedSourceIDs, ["mic-1", "app-1"])
        XCTAssertEqual(decoded.sourceLanguageOverrides, ["app-1": "fr"])
        XCTAssertEqual(
            decoded.sourceOutputLanguageOverrides,
            ["mic-1": "zh-Hans", "app-1": "de"]
        )
        XCTAssertEqual(decoded.inputLanguageID, "en")
        XCTAssertEqual(decoded.outputLanguageID, "ja")
        XCTAssertEqual(decoded.interfaceLanguageID, "en")
        XCTAssertEqual(decoded.glossary, ["CEO": "Chief Executive Officer"])
    }

    func testInvisibleInRecordingDefaultsToOffForSettingsSavedBeforeTheToggleExisted() throws {
        let json = """
        {
          "selectedSourceID": "mic-1",
          "inputLanguageID": "en",
          "outputLanguageID": "ja",
          "overlayStyle": {
            "translatedFontSize": 20,
            "sourceFontSize": 16,
            "backgroundOpacity": 0.7,
            "topInset": 12,
            "widthRatio": 0.82,
            "minWidth": 720,
            "maxWidth": 1440,
            "clickThrough": true,
            "translatedFirst": true
          },
          "subtitleMode": "balanced",
          "subtitleDisplayMode": "both",
          "glossary": {}
        }
        """

        let settings = try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))

        XCTAssertFalse(settings.overlayStyle.invisibleInRecording)
    }

    func testInvisibleInRecordingSurvivesAnEncodeDecodeRoundTrip() throws {
        var style = OverlayStyle.default
        style.invisibleInRecording = true

        let data = try JSONEncoder().encode(style)
        let decoded = try JSONDecoder().decode(OverlayStyle.self, from: data)

        XCTAssertTrue(decoded.invisibleInRecording)
    }
}
