import SwiftUI

private struct LearningsInsightRow: Identifiable {
    let id = UUID()
    let kind: LearningsAttributionKind
    let icon: String
    let title: String
    let detail: String
    let color: Color

    init(item: LearningsAttributionItem) {
        self.kind = item.kind
        self.title = item.title
        self.detail = item.detail

        switch item.kind {
        case .learnedRule:
            self.icon = "sparkles"
            self.color = .orange
        case .ruleEvidence:
            self.icon = "doc.text.magnifyingglass"
            self.color = .mint
        case .honingPreference:
            self.icon = "slider.horizontal.3"
            self.color = .teal
        }
    }
}

struct LiquidGlassLearningsButton: View {
    let file: FileItem
    let suggestion: FolderSuggestion
    var learningsManager: LearningsManager? = nil

    @State private var showPopover = false

    private var attribution: FileLearningsAttribution {
        FileLearningsAttributionResolver.resolve(
            file: file,
            suggestion: suggestion,
            profile: learningsManager?.currentProfile
        )
    }

    private var learningRows: [LearningsInsightRow] {
        attribution.learningsItems.map(LearningsInsightRow.init(item:))
    }

    private var honingRows: [LearningsInsightRow] {
        attribution.honingItems.map(LearningsInsightRow.init(item:))
    }

    private var hasContent: Bool {
        attribution.hasContent
    }

    var body: some View {
        if hasContent {
            Button {
                showPopover.toggle()
            } label: {
                Image(systemName: "brain.head.profile")
                    .font(.caption2)
                    .foregroundStyle(showPopover ? .teal : .secondary)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("FileLearningsButton")
            .help("View learnings used for this file")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: "brain.head.profile")
                            .font(.caption)
                            .foregroundStyle(.teal)

                        Text("Learnings Used")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundStyle(.primary)

                        Spacer()

                        Text(file.displayName)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }

                    if !learningRows.isEmpty {
                        sectionHeader("Learnings")
                        ForEach(learningRows) { row in
                            insightRow(row)
                        }
                    }

                    if !honingRows.isEmpty {
                        sectionHeader("Honing")
                        ForEach(honingRows) { row in
                            insightRow(row)
                        }
                    }
                }
                .padding(12)
                .frame(minWidth: 240, maxWidth: 340)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.quaternary)
            .textCase(.uppercase)
    }

    private func insightRow(_ row: LearningsInsightRow) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: row.icon)
                .font(.caption2)
                .foregroundStyle(row.color)
                .frame(width: 12, alignment: .center)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Text(row.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
    }
}
