import AppKit
import SwiftUI
import XCTest
@testable import v2s

/// Renders the new SwiftUI surfaces to PNG with `ImageRenderer` (no screen-recording permission
/// needed). Skipped unless `V2S_SNAPSHOT_DIR` is set; used to produce the screenshots in the report.
@MainActor
final class UISnapshotTests: XCTestCase {
    private var outputDirectory: URL?

    override func setUpWithError() throws {
        guard let path = ProcessInfo.processInfo.environment["V2S_SNAPSHOT_DIR"] else {
            throw XCTSkip("V2S_SNAPSHOT_DIR not set")
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        outputDirectory = url
    }

    private func makeModel() -> AppModel {
        let settingsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v2s-snapshot-\(UUID().uuidString).json")
        let model = AppModel(settingsStore: SettingsStore(fileURL: settingsURL), sourceCatalogService: SourceCatalogService())
        model.interfaceLanguageID = "en"
        return model
    }

    private let now = Date(timeIntervalSince1970: 1_761_100_000)

    private var sampleEntries: [TranscriptEntry] {
        let lines: [(String, String, String)] = [
            ("おはようございます。今日もよろしくお願いします。", "Selamat pagi. Mohon kerja samanya hari ini.", "Zoom"),
            ("昨日の会議の内容をもう一度確認させてください。", "Izinkan saya mengonfirmasi kembali isi rapat kemarin.", "Zoom"),
            ("来週の月曜日までに資料を準備しておいてもらえると助かりますけど、難しければ早めに教えてください。",
             "Akan sangat membantu jika Anda dapat menyiapkan materi sebelum Senin depan, tetapi jika sulit, mohon beri tahu saya lebih awal.", "Zoom"),
            ("この商品は先月発売されたばかりですが、もう十万個も売れていて、お客様からとても人気があります。",
             "Produk ini baru dirilis bulan lalu, tetapi sudah terjual lebih dari 100.000 unit dan sangat disukai pelanggan.", "Zoom"),
            ("では次の議題に移りますが、まず先月の売り上げについてご報告します。", "", "Zoom")
        ]
        return lines.enumerated().map { index, line in
            TranscriptEntry(
                id: UUID(), sourceText: line.0, translatedText: line.1,
                timestamp: now.addingTimeInterval(Double(index) * 7), sourceName: line.2
            )
        }
    }

    /// Hosts the view in an off-screen window and caches its display, so AppKit-backed controls
    /// (segmented pickers, text fields) render too, which `ImageRenderer` cannot do.
    private func render<V: View>(_ view: V, name: String, size: CGSize, scheme: ColorScheme) throws {
        let framed = view
            .frame(width: size.width, height: size.height, alignment: .top)
            .background(scheme == .dark ? Color(red: 0.12, green: 0.12, blue: 0.13) : Color(red: 0.96, green: 0.96, blue: 0.97))
            .environment(\.colorScheme, scheme)
        let hosting = NSHostingView(rootView: framed)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        window.contentView = hosting
        window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
        window.orderFront(nil)
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        hosting.layoutSubtreeIfNeeded()

        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: try XCTUnwrap(outputDirectory).appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
        window.orderOut(nil)
    }

    /// The history rows exactly as the Conversation tab draws them (a plain stack, because an
    /// off-screen renderer cannot size a lazy scroll view).
    private struct HistorySnapshot: View {
        let entries: [TranscriptEntry]
        let draft: String

        var body: some View {
            VStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    ConversationRow(entry: entry, index: index, isLatest: index == entries.count - 1, showsSourceName: true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft).font(.callout.italic()).foregroundStyle(.secondary.opacity(0.8))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 17)
                .padding(.vertical, 9)
                Spacer(minLength: 0)
            }
        }
    }

    func testRenderConversationHistory() throws {
        for scheme in [ColorScheme.light, .dark] {
            try render(
                HistorySnapshot(entries: sampleEntries, draft: "それでは、まず先月の売り上げについて"),
                name: "conversation", size: CGSize(width: 560, height: 520), scheme: scheme
            )
        }
    }

    func testRenderSettingsCards() throws {
        let model = makeModel()
        model.readingGlossary = [
            ReadingGlossaryEntry(term: "石橋誠", reading: "いしばしまこと", language: "ja"),
            ReadingGlossaryEntry(term: "Symphonics", reading: "symfonics", language: nil)
        ]
        for scheme in [ColorScheme.light, .dark] {
            try render(
                VStack(spacing: 14) {
                    TranslationQualityCard(model: model)
                    SegmentationSettingsCard(model: model)
                    ReadingGlossaryCard(model: model)
                    OverlayThemeCard(model: model)
                }
                .padding(20),
                name: "settings", size: CGSize(width: 520, height: 900), scheme: scheme
            )
        }
    }
}
