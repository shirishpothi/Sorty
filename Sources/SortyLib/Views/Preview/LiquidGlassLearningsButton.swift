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
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .frame(width: 22, height: 22)
                        .overlay(
                            Circle()
                                .stroke(
                                    LinearGradient(
                                        colors: [
                                            Color.white.opacity(showPopover ? 0.5 : 0.3),
                                            Color.white.opacity(0.05)
                                        ],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    ),
                                    lineWidth: 0.5
                                )
                        )
                        .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(showPopover ? .teal : Color.secondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("FileLearningsButton")
            .help("View attributable learnings and honing signals used for this file")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        ZStack {
                            Circle()
                                .fill(Color.teal.opacity(0.12))
                                .frame(width: 28, height: 28)

                            Image(systemName: "brain.head.profile")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.teal)
                        }

                        VStack(alignment: .leading, spacing: 1) {
                            Text("Learnings Used")
                                .font(.caption)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)

                            Text(file.displayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Spacer()
                    }
                    .padding(.bottom, 10)

                    Divider()
                        .opacity(0.4)
                        .padding(.bottom, 10)

                    VStack(alignment: .leading, spacing: 10) {
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
                }
                .padding(14)
                .frame(minWidth: 250, maxWidth: 360)
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .padding(.top, 2)
    }

    private func insightRow(_ row: LearningsInsightRow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: row.icon)
                    .font(.caption)
                    .foregroundStyle(row.color)

                Text(row.title)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)
            }

            Text(row.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
        }
    }
}
