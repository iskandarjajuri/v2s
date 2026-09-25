import SwiftUI

struct StatusBarPopoverView: View {
    @ObservedObject var model: AppModel
    let closePopover: () -> Void
    let openAdvancedSettings: () -> Void
    let showTranscript: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
            Divider().padding(.horizontal, 16)
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    sourceSection
                    languageSection
                    overlaySection
                }
                .padding(16)
            }
            Divider().padding(.horizontal, 16)
            footerSection
        }
        .frame(width: 340)
        .background(.regularMaterial)
        .environment(\.locale, model.interfaceLocale)
        .v2sTranslationHost(model: model)
        .onChange(of: model.sessionState) { _, newState in
            if newState == .running {
                closePopover()
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Image(systemName: "captions.bubble.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 1) {
                    Text("v2s")
                        .font(.headline)
                    Text(model.statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    VersionLink(
                        versionText: model.appVersionDisplayText,
                        repositoryURL: model.appRepositoryURL,
                        font: .caption2.monospacedDigit()
                    )
                    Text(model.sessionBadgeText)
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.fill.tertiary, in: Capsule())
                }
            }
            Button {
                model.toggleSession()
            } label: {
                SessionActionButtonLabel(
                    title: model.sessionButtonTitle,
                    symbolName: model.sessionButtonSymbolName,
                    showsActivity: model.showsSessionWaitIndicator
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSessionButtonDisabled)
            if let status = model.captureHealthStatus {
                CaptureHealthCard(
                    status: status,
                    text: model.captureHealthText ?? "",
                    level: model.captureAudioLevel,
                    label: model.localized(.audioInput),
                    settingsTitle: model.localized(.openAudioRecordingSettings),
                    openSettings: model.openSystemAudioRecordingSettings
                )
            }
        }
        .padding(16)
    }

    // MARK: - Input Source

    private var sourceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(model.localized(.inputSource), icon: "mic.fill")
            SettingsControlRow(label: model.localized(.sourceShort)) {
                SourceMultiSelectPicker(
                    sources: model.allSources,
                    interfaceLanguageID: model.resolvedInterfaceLanguageID,
                    emptyTitle: model.allSources.isEmpty ? model.localized(.noSources) : model.localized(.choose),
                    selection: model.selectedSourcesBinding
                )
            }
            SecondaryRefreshButton(
                title: model.localized(.refreshSources),
                action: model.refreshSources
            )
        }
    }

    // MARK: - Languages

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionHeader(model.localized(.languages), icon: "globe")
            SettingsControlRow(label: model.localized(.defaultInputLanguage)) {
                CommonLanguageMenuPicker(
                    interfaceLanguageID: model.resolvedInterfaceLanguageID,
                    options: model.speechLanguageOptions,
                    selection: model.inputLanguageSelectionBinding
                )
                .disabled(model.isLanguagePairLocked)
            }
            if let notice = model.serverSpeechRecognitionNotice {
                Label(notice, systemImage: "icloud")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            SettingsControlRow(label: model.localized(.defaultSubtitleLanguage)) {
                CommonLanguageMenuPicker(
                    interfaceLanguageID: model.resolvedInterfaceLanguageID,
                    options: model.translationLanguageOptions,
                    selection: model.outputLanguageSelectionBinding
                )
                .disabled(model.isLanguagePairLocked)
            }
            SettingsControlRow(label: model.localized(.modeShort)) {
                SubtitleModeMenuPicker(
                    interfaceLanguageID: model.resolvedInterfaceLanguageID,
                    showsDetail: false,
                    selection: model.subtitleModeSelectionBinding
                )
            }
            SettingsControlRow(label: model.localized(.displayShort)) {
                SubtitleDisplayModeMenuPicker(
                    interfaceLanguageID: model.resolvedInterfaceLanguageID,
                    selection: model.subtitleDisplayModeSelectionBinding
                )
            }
            LanguageResourcesFooter(model: model)
        }
    }

    // MARK: - Overlay

    private var overlaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionHeader(model.localized(.overlay), icon: "rectangle.on.rectangle")
                Spacer()
                Button {
                    showTranscript()
                } label: {
                    Text(model.localized(.transcript))
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    if model.isOverlayVisible { model.toggleOverlayVisibility() }
                    else { model.showOverlayPreview() }
                } label: {
                    Text(model.isOverlayVisible ? model.localized(.hideOverlay) : model.localized(.showPreview))
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            VStack(spacing: 6) {
                SettingsControlRow(label: model.localized(.textOutline)) {
                    Toggle("", isOn: textOutlineEnabledBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
                SettingsControlRow(label: model.localized(.attachToSource)) {
                    Toggle("", isOn: attachToSourceBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                }
            }
            VStack(spacing: 8) {
                compactSlider(
                    label: model.localized(.opacity),
                    value: overlayOpacityBinding, in: 0.0 ... 1.0,
                    display: "\(Int((model.overlayStyle.backgroundOpacity * 100).rounded()))%"
                )
                compactSlider(
                    label: model.localized(.fontSize),
                    value: translatedFontBinding, in: 8 ... 34,
                    display: "\(Int(model.overlayStyle.translatedFontSize.rounded()))pt"
                )
                compactSlider(
                    label: model.localized(.sourceSize),
                    value: sourceFontBinding, in: 5 ... 28,
                    display: "\(Int(model.overlayStyle.sourceFontSize.rounded()))pt"
                )
            }
        }
    }

    // MARK: - Footer

    private var footerSection: some View {
        HStack {
            Button { openAdvancedSettings() } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help(model.localized(.advancedSettings))
            Button { quitApp() } label: {
                Image(systemName: "power")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(model.localized(.quit))
            .help(model.localized(.quit))
            Spacer()
            if model.selectedSources.isEmpty == false {
                Text(model.selectedSourceDisplayName)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Layout helpers

    private func sectionHeader(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.primary)
    }

    private func compactSlider(
        label: String,
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        display: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(display)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .controlSize(.small)
        }
    }

    // MARK: - Bindings

    private var overlayOpacityBinding: Binding<Double> {
        Binding(
            get: { model.overlayStyle.backgroundOpacity },
            set: { v in model.updateOverlayStyle { $0.backgroundOpacity = v } }
        )
    }
    private var translatedFontBinding: Binding<Double> {
        Binding(
            get: { model.overlayStyle.translatedFontSize },
            set: { v in model.updateOverlayStyle { $0.translatedFontSize = v } }
        )
    }
    private var textOutlineEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.overlayStyle.showsTextOutline },
            set: { v in model.updateOverlayStyle { $0.showsTextOutline = v } }
        )
    }
    private var attachToSourceBinding: Binding<Bool> {
        Binding(
            get: { model.overlayStyle.attachToSource },
            set: { v in model.updateOverlayStyle { $0.attachToSource = v } }
        )
    }
    private var sourceFontBinding: Binding<Double> {
        Binding(
            get: { model.overlayStyle.sourceFontSize },
            set: { v in model.updateOverlayStyle { $0.sourceFontSize = v } }
        )
    }
}

struct VersionLink: View {
    @Environment(\.openURL) private var openURL

    let versionText: String
    let repositoryURL: URL?
    let font: Font

    var body: some View {
        Group {
            if let repositoryURL {
                Button {
                    openURL(repositoryURL)
                } label: {
                    versionLabel
                }
                .buttonStyle(.plain)
                .help(repositoryURL.absoluteString)
            } else {
                versionLabel
                    .help(versionText)
            }
        }
    }

    private var versionLabel: some View {
        Text(verbatim: versionText)
            .font(font)
            .foregroundStyle(.secondary)
    }
}

/// 「いま音が聞こえているか」を一目で分かるようにするカード。字幕が出ない原因の大半は
/// 「対象アプリが音を出していない」か「権限が無い」なので、その 2 つを言葉とメーターで区別する。
private struct CaptureHealthCard: View {
    let status: CaptureHealthStatus
    let text: String
    let level: Float
    let label: String
    let settingsTitle: String
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: symbolName)
                    .foregroundStyle(tint)
                    .frame(width: 16)
                Text(label)
                    .font(.caption.weight(.medium))
                AudioLevelMeter(level: level, tint: tint)
                    .frame(height: 6)
            }
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if status == .permissionProblemSuspected {
                Button(settingsTitle, action: openSettings)
                    .controlSize(.small)
            }
        }
        .padding(10)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .combine)
    }

    private var symbolName: String {
        switch status {
        case .hearingAudio:
            return "waveform"
        case .starting, .waitingForSourceAudio:
            return "speaker.wave.1"
        case .reconnecting:
            return "arrow.triangle.2.circlepath"
        case .permissionProblemSuspected:
            return "exclamationmark.triangle.fill"
        }
    }

    private var tint: Color {
        switch status {
        case .hearingAudio:
            return .green
        case .starting, .waitingForSourceAudio:
            return .secondary
        case .reconnecting:
            return .orange
        case .permissionProblemSuspected:
            return .red
        }
    }
}

private struct AudioLevelMeter: View {
    let level: Float
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule()
                    .fill(tint)
                    .frame(width: proxy.size.width * CGFloat(min(max(level, 0), 1)))
            }
        }
        .animation(.linear(duration: 0.1), value: level)
        .accessibilityHidden(true)
    }
}
