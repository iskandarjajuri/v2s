import AppKit
import SwiftUI
import UniformTypeIdentifiers

// Settings cards for the segmentation, translation and name-dictionary features.
// Kept apart from SettingsView so each card only depends on the model.

private struct SettingsCardChrome<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct CardHeader: View {
    let title: String
    let icon: String

    var body: some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .padding(.bottom, 4)
    }
}

// MARK: - Segmentation

struct SegmentationSettingsCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCardChrome {
            CardHeader(title: model.localized(.segmentationSection), icon: "scissors")
            Toggle(model.localized(.segmentationEnabled), isOn: binding(\.isEnabled))
            Text(model.localized(.segmentationHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.segmentation.isEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.localized(.maxContinuousSpeech))
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "%.0f s", model.segmentation.maxContinuousSpeechSeconds))
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(value: binding(\.maxContinuousSpeechSeconds), in: 6 ... 24, step: 1)
                        .controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(model.localized(.stableLeadingDelay))
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Text("\(model.segmentation.stableLeadingMs) ms")
                            .font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    Slider(
                        value: Binding(
                            get: { Double(model.segmentation.stableLeadingMs) },
                            set: { model.segmentation.stableLeadingMs = Int($0) }
                        ),
                        in: 120 ... 600,
                        step: 10
                    )
                    .controlSize(.small)
                }
                Toggle(model.localized(.cutAtJapaneseClauseEndings), isOn: binding(\.cutAtJapaneseClauseEndings))
                    .font(.callout)
            }
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<SegmentationSettings, Value>) -> Binding<Value> {
        Binding(
            get: { model.segmentation[keyPath: keyPath] },
            set: { model.segmentation[keyPath: keyPath] = $0 }
        )
    }
}

// MARK: - Translation quality

struct TranslationQualityCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCardChrome {
            CardHeader(title: model.localized(.translationQuality), icon: "bolt.badge.clock")
            Picker("", selection: $model.translationMode) {
                Text(model.localized(.translationModeProgressive)).tag(TranslationQualityMode.progressive)
                Text(model.localized(.translationModeNaturalOnly)).tag(TranslationQualityMode.naturalOnly)
                Text(model.localized(.translationModeFastOnly)).tag(TranslationQualityMode.fastOnly)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(model.localized(.translationModeHelp))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle(model.localized(.cleanSpokenText), isOn: $model.cleansSpokenText)
            Text(model.localized(.cleanSpokenTextHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Reading-based dictionary

struct ReadingGlossaryCard: View {
    @ObservedObject var model: AppModel
    @State private var term = ""
    @State private var reading = ""
    @State private var importError: String?

    var body: some View {
        SettingsCardChrome {
            HStack {
                CardHeader(title: model.localized(.readingGlossary), icon: "ear")
                Spacer()
                Button(model.localized(.importFile)) { importFile() }
                    .controlSize(.small)
                Button(model.localized(.exportTranscript)) { exportFile() }
                    .controlSize(.small)
                    .disabled(model.readingGlossary.isEmpty)
            }
            Text(model.localized(.readingGlossaryHint))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if model.readingGlossary.isEmpty {
                Text(model.localized(.readingGlossaryEmpty))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                ForEach(model.readingGlossary) { entry in
                    HStack {
                        Text(entry.term).font(.callout)
                        if entry.reading.isEmpty == false {
                            Text(entry.reading).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.readingGlossary.removeAll { $0.id == entry.id }
                        } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.red.opacity(0.8))
                        }
                        .buttonStyle(.plain)
                    }
                    Divider()
                }
            }

            HStack(spacing: 8) {
                TextField(model.localized(.readingGlossaryTerm), text: $term)
                    .textFieldStyle(.roundedBorder)
                TextField(model.localized(.readingGlossaryReading), text: $reading)
                    .textFieldStyle(.roundedBorder)
                Button {
                    addEntry()
                } label: {
                    Image(systemName: "plus.circle.fill").foregroundStyle(.green)
                }
                .buttonStyle(.plain)
                .disabled(term.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if let importError {
                Text(importError).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func addEntry() {
        let trimmedTerm = term.trimmingCharacters(in: .whitespaces)
        guard trimmedTerm.isEmpty == false else { return }
        let entry = ReadingGlossaryEntry(
            term: trimmedTerm,
            reading: reading.trimmingCharacters(in: .whitespaces),
            language: nil
        )
        if model.readingGlossary.contains(where: { $0.id == entry.id }) == false {
            model.readingGlossary.append(entry)
        }
        term = ""
        reading = ""
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let file = try ReadingGlossaryFile.decode(from: Data(contentsOf: url))
            let existing = Set(model.readingGlossary.map(\.id))
            model.readingGlossary.append(contentsOf: file.entries.filter { existing.contains($0.id) == false })
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "v2s-glossary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ReadingGlossaryFile(entries: model.readingGlossary).encoded().write(to: url, options: .atomic)
            importError = nil
        } catch {
            importError = error.localizedDescription
        }
    }
}

// MARK: - Overlay theme and position

struct OverlayThemeCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        SettingsCardChrome {
            CardHeader(title: model.localized(.overlayTheme), icon: "paintpalette")
            HStack(spacing: 8) {
                ForEach(OverlayTheme.allCases) { theme in
                    Button {
                        model.updateOverlayStyle { theme.apply(to: &$0) }
                    } label: {
                        VStack(spacing: 4) {
                            ThemeSwatch(theme: theme)
                            Text(title(for: theme)).font(.caption)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Picker(model.localized(.overlayPosition), selection: anchorBinding) {
                Text(model.localized(.overlayPositionTop)).tag(false)
                Text(model.localized(.overlayPositionBottom)).tag(true)
            }
            .pickerStyle(.segmented)
        }
    }

    private var anchorBinding: Binding<Bool> {
        Binding(
            get: { model.overlayStyle.anchorsToBottom },
            set: { value in model.updateOverlayStyle { $0.anchorsToBottom = value } }
        )
    }

    private func title(for theme: OverlayTheme) -> String {
        switch theme {
        case .dark: return model.localized(.overlayThemeDark)
        case .light: return model.localized(.overlayThemeLight)
        case .highContrast: return model.localized(.overlayThemeContrast)
        case .colorful: return model.localized(.overlayThemeColorful)
        }
    }
}

private struct ThemeSwatch: View {
    let theme: OverlayTheme

    var body: some View {
        var style = OverlayStyle.default
        theme.apply(to: &style)
        return RoundedRectangle(cornerRadius: 6)
            .fill(style.backgroundColor.color.opacity(max(style.backgroundOpacity, 0.55)))
            .overlay(
                VStack(spacing: 1) {
                    Text("字幕").font(.system(size: 11, weight: .semibold)).foregroundStyle(style.subtitleColor.color)
                    Text("Subtitle").font(.system(size: 8)).foregroundStyle(style.sourceSubtitleColor.color)
                }
            )
            .frame(width: 74, height: 40)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.separator, lineWidth: 1))
    }
}
