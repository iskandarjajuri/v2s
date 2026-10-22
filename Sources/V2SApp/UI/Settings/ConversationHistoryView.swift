import SwiftUI

/// Scrollable record of the conversation: one row per committed caption with its timestamp,
/// the original line and the translation in distinct colors, alternating tints between
/// segments, the newest row highlighted, and the live partial shown muted at the bottom.
///
/// Rows are `Equatable` and live in a `LazyVStack`, so a new caption (or a late translation)
/// only redraws the rows that changed instead of the whole history.
struct ConversationHistoryView: View {
    @ObservedObject var model: AppModel
    @State private var followsLatest = true

    private static let bottomID = "conversation-bottom"

    var body: some View {
        let entries = model.transcriptEntries
        let latestID = entries.last?.id

        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                            ConversationRow(
                                entry: entry,
                                index: index,
                                isLatest: entry.id == latestID,
                                showsSourceName: model.selectedSources.count > 1
                            )
                            .equatable()
                        }
                        LiveDraftRow(model: model)
                        Color.clear.frame(height: 1).id(Self.bottomID)
                            .onAppear { followsLatest = true }
                            .onDisappear { followsLatest = false }
                    }
                }
                .onChange(of: entries.count) { _, _ in
                    guard followsLatest else { return }
                    withAnimation(.easeOut(duration: 0.18)) {
                        proxy.scrollTo(Self.bottomID, anchor: .bottom)
                    }
                }

                if followsLatest == false, entries.isEmpty == false {
                    Button {
                        followsLatest = true
                        withAnimation { proxy.scrollTo(Self.bottomID, anchor: .bottom) }
                    } label: {
                        Label(model.localized(.jumpToLatest), systemImage: "arrow.down.to.line")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .padding(12)
                }
            }
            .overlay {
                if entries.isEmpty {
                    Text("–")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

struct ConversationRow: View, Equatable {
    let entry: TranscriptEntry
    let index: Int
    let isLatest: Bool
    let showsSourceName: Bool

    static func == (lhs: ConversationRow, rhs: ConversationRow) -> Bool {
        lhs.entry == rhs.entry && lhs.index == rhs.index
            && lhs.isLatest == rhs.isLatest && lhs.showsSourceName == rhs.showsSourceName
    }

    /// Two translation hues alternate per segment so a long exchange stays easy to follow.
    private var translationColor: Color {
        index.isMultiple(of: 2) ? Color.blue : Color.teal
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(entry.timestamp, format: .dateTime.hour().minute().second())
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                    if showsSourceName, entry.sourceName.isEmpty == false {
                        Text(entry.sourceName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }

                if entry.sourceText.isEmpty == false {
                    Text(entry.sourceText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if entry.translatedText.isEmpty == false, entry.translatedText != entry.sourceText {
                    Text(entry.translatedText)
                        .font(.body.weight(isLatest ? .semibold : .medium))
                        .foregroundStyle(translationColor)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if entry.translatedText.isEmpty {
                    Text("…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(rowBackground)
        // The accent bar is a background so it never claims height of its own.
        .background(alignment: .leading) {
            Rectangle()
                .fill(isLatest ? Color.accentColor : Color.clear)
                .frame(width: 3)
        }
        .animation(nil, value: entry)
    }

    private var rowBackground: some ShapeStyle {
        if isLatest {
            return AnyShapeStyle(Color.accentColor.opacity(0.10))
        }
        return AnyShapeStyle(index.isMultiple(of: 2) ? Color.primary.opacity(0.035) : Color.clear)
    }
}

/// The caption being spoken right now: muted and italic until it is committed, then it
/// becomes a regular (firm) row. Observes the overlay's draft state only.
private struct LiveDraftRow: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if let draft = model.overlayState?.draftSourceText, draft.isEmpty == false {
            VStack(alignment: .leading, spacing: 3) {
                Text(draft)
                    .font(.callout.italic())
                    .foregroundStyle(.secondary.opacity(0.8))
                if let translated = model.overlayState?.visibleDraftTranslatedText(
                    for: draft,
                    promotionID: model.overlayState?.draftPromotionID
                ), translated.isEmpty == false {
                    Text(translated)
                        .font(.body.italic())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 17)
            .padding(.vertical, 9)
        }
    }
}
