import AppKit
import Foundation
import SwiftUI

struct OverlayColor: Codable, Equatable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let defaultSubtitle = OverlayColor(
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        alpha: 1.0
    )
    /// 原文（ソース）行の既定色。翻訳行の白に対して十分なコントラスト差を持ちつつ、
    /// 暗い背景でも視認性を保てる淡いシアン。
    static let defaultSourceSubtitle = OverlayColor(
        red: 0.62,
        green: 0.86,
        blue: 1.0,
        alpha: 1.0
    )
    static let defaultBackground = OverlayColor(
        red: 0.0,
        green: 0.0,
        blue: 0.0,
        alpha: 1.0
    )
    static let defaultTextOutline = OverlayColor(
        red: 1.0,
        green: 1.0,
        blue: 1.0,
        alpha: 1.0
    )

    init(
        red: Double,
        green: Double,
        blue: Double,
        alpha: Double = 1.0
    ) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    init(color: Color) {
        let srgbColor = NSColor(color).usingColorSpace(.sRGB)
            ?? NSColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
        self.init(
            red: Double(srgbColor.redComponent),
            green: Double(srgbColor.greenComponent),
            blue: Double(srgbColor.blueComponent),
            alpha: Double(srgbColor.alphaComponent)
        )
    }

    var color: Color {
        Color(
            .sRGB,
            red: red,
            green: green,
            blue: blue,
            opacity: alpha
        )
    }
}

struct OverlayStyle: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case targetDisplayID
        case topInset
        case widthRatio
        case minWidth
        case maxWidth
        case backgroundOpacity
        case subtitleColor
        case sourceSubtitleColor
        case backgroundColor
        case showsTextOutline = "usesWhiteTextOutline"
        case textOutlineColor
        case translatedFontSize
        case sourceFontSize
        case clickThrough
        case translatedFirst
        case overlayScaleFactor
        case attachToSource
        case invisibleInRecording
        case anchorsToBottom
    }

    private enum LegacyCodingKeys: String, CodingKey {
        case usesHighContrastBorder
    }

    var targetDisplayID: String?
    var topInset: Double
    var widthRatio: Double
    var minWidth: Double
    var maxWidth: Double
    var backgroundOpacity: Double
    /// 翻訳行の色。
    var subtitleColor: OverlayColor
    /// 原文行の色。翻訳と原文を一目で区別するため別々に持つ。
    var sourceSubtitleColor: OverlayColor
    var backgroundColor: OverlayColor
    var showsTextOutline: Bool
    var textOutlineColor: OverlayColor
    var translatedFontSize: Double
    var sourceFontSize: Double
    var clickThrough: Bool
    // Retained for backwards compatibility with persisted settings.
    var translatedFirst: Bool
    var overlayScaleFactor: Double
    var attachToSource: Bool
    /// Keeps the overlay on screen for the user while excluding it from screen
    /// recordings, screenshots, and shared screens.
    var invisibleInRecording: Bool
    /// Docks the subtitles to the bottom of the usable screen (above the Dock) instead of the top.
    /// `topInset` is then the gap to the bottom edge.
    var anchorsToBottom: Bool

    var scaledTranslatedFontSize: Double { translatedFontSize * overlayScaleFactor }
    var scaledSourceFontSize: Double { sourceFontSize * overlayScaleFactor }

    static let `default` = OverlayStyle(
        targetDisplayID: nil,
        topInset: 12,
        widthRatio: 0.82,
        minWidth: 720,
        maxWidth: 1440,
        backgroundOpacity: 0.32,
        subtitleColor: .defaultSubtitle,
        sourceSubtitleColor: .defaultSourceSubtitle,
        backgroundColor: .defaultBackground,
        showsTextOutline: false,
        textOutlineColor: .defaultTextOutline,
        translatedFontSize: 24,
        sourceFontSize: 18,
        clickThrough: true,
        translatedFirst: true,
        overlayScaleFactor: 1.0,
        attachToSource: false,
        invisibleInRecording: false,
        anchorsToBottom: false
    )

    init(
        targetDisplayID: String?,
        topInset: Double,
        widthRatio: Double,
        minWidth: Double,
        maxWidth: Double,
        backgroundOpacity: Double,
        subtitleColor: OverlayColor,
        sourceSubtitleColor: OverlayColor = .defaultSourceSubtitle,
        backgroundColor: OverlayColor,
        showsTextOutline: Bool,
        textOutlineColor: OverlayColor,
        translatedFontSize: Double,
        sourceFontSize: Double,
        clickThrough: Bool,
        translatedFirst: Bool,
        overlayScaleFactor: Double = 1.0,
        attachToSource: Bool = false,
        invisibleInRecording: Bool = false,
        anchorsToBottom: Bool = false
    ) {
        self.targetDisplayID = targetDisplayID
        self.topInset = topInset
        self.widthRatio = widthRatio
        self.minWidth = minWidth
        self.maxWidth = maxWidth
        self.backgroundOpacity = backgroundOpacity
        self.subtitleColor = subtitleColor
        self.sourceSubtitleColor = sourceSubtitleColor
        self.backgroundColor = backgroundColor
        self.showsTextOutline = showsTextOutline
        self.textOutlineColor = textOutlineColor
        self.translatedFontSize = translatedFontSize
        self.sourceFontSize = sourceFontSize
        self.clickThrough = clickThrough
        self.translatedFirst = translatedFirst
        self.overlayScaleFactor = overlayScaleFactor
        self.attachToSource = attachToSource
        self.invisibleInRecording = invisibleInRecording
        self.anchorsToBottom = anchorsToBottom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let legacy = try decoder.container(keyedBy: LegacyCodingKeys.self)
        targetDisplayID    = try c.decodeIfPresent(String.self, forKey: .targetDisplayID)
        topInset           = try c.decode(Double.self, forKey: .topInset)
        widthRatio         = try c.decode(Double.self, forKey: .widthRatio)
        minWidth           = try c.decode(Double.self, forKey: .minWidth)
        maxWidth           = try c.decode(Double.self, forKey: .maxWidth)
        backgroundOpacity  = try c.decode(Double.self, forKey: .backgroundOpacity)
        subtitleColor      = try c.decodeIfPresent(OverlayColor.self, forKey: .subtitleColor)
            ?? .defaultSubtitle
        sourceSubtitleColor = try c.decodeIfPresent(OverlayColor.self, forKey: .sourceSubtitleColor)
            ?? .defaultSourceSubtitle
        backgroundColor    = try c.decodeIfPresent(OverlayColor.self, forKey: .backgroundColor)
            ?? .defaultBackground
        let legacyWhiteOutline = try legacy.decodeIfPresent(Bool.self, forKey: .usesHighContrastBorder)
        showsTextOutline = try c.decodeIfPresent(Bool.self, forKey: .showsTextOutline)
            ?? legacyWhiteOutline
            ?? false
        textOutlineColor  = try c.decodeIfPresent(OverlayColor.self, forKey: .textOutlineColor)
            ?? .defaultTextOutline
        translatedFontSize = try c.decode(Double.self, forKey: .translatedFontSize)
        sourceFontSize     = try c.decode(Double.self, forKey: .sourceFontSize)
        clickThrough       = try c.decode(Bool.self,   forKey: .clickThrough)
        translatedFirst    = try c.decodeIfPresent(Bool.self, forKey: .translatedFirst) ?? true
        overlayScaleFactor = try c.decodeIfPresent(Double.self, forKey: .overlayScaleFactor) ?? 1.0
        attachToSource = try c.decodeIfPresent(Bool.self, forKey: .attachToSource) ?? false
        invisibleInRecording = try c.decodeIfPresent(Bool.self, forKey: .invisibleInRecording) ?? false
        anchorsToBottom = try c.decodeIfPresent(Bool.self, forKey: .anchorsToBottom) ?? false
    }
}


/// One-tap color schemes for the subtitle overlay. They only set colors (and the background
/// strength where legibility needs it); sizes, position and the rest stay as the user left them.
enum OverlayTheme: String, CaseIterable, Identifiable {
    case dark
    case light
    case highContrast
    case colorful

    var id: String { rawValue }

    func apply(to style: inout OverlayStyle) {
        switch self {
        case .dark:
            style.subtitleColor = OverlayColor(red: 1, green: 1, blue: 1)
            style.sourceSubtitleColor = OverlayColor(red: 0.62, green: 0.86, blue: 1)
            style.backgroundColor = OverlayColor(red: 0, green: 0, blue: 0)
            style.backgroundOpacity = max(style.backgroundOpacity, 0.32)
        case .light:
            style.subtitleColor = OverlayColor(red: 0.08, green: 0.08, blue: 0.1)
            style.sourceSubtitleColor = OverlayColor(red: 0.2, green: 0.36, blue: 0.62)
            style.backgroundColor = OverlayColor(red: 1, green: 1, blue: 1)
            style.backgroundOpacity = max(style.backgroundOpacity, 0.6)
        case .highContrast:
            style.subtitleColor = OverlayColor(red: 1, green: 0.93, blue: 0.2)
            style.sourceSubtitleColor = OverlayColor(red: 1, green: 1, blue: 1)
            style.backgroundColor = OverlayColor(red: 0, green: 0, blue: 0)
            style.backgroundOpacity = max(style.backgroundOpacity, 0.55)
        case .colorful:
            style.subtitleColor = OverlayColor(red: 0.55, green: 1, blue: 0.7)
            style.sourceSubtitleColor = OverlayColor(red: 1, green: 0.78, blue: 0.45)
            style.backgroundColor = OverlayColor(red: 0.05, green: 0.06, blue: 0.14)
            style.backgroundOpacity = max(style.backgroundOpacity, 0.4)
        }
    }
}
