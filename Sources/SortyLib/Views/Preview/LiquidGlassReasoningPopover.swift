//
//  LiquidGlassReasoningPopover.swift
//  Sorty
//
//  Liquid glass style popover for displaying AI reasoning and learned rule context.
//

import SwiftUI

struct LiquidGlassReasoningButton: View {
    let suggestion: FolderSuggestion
    var learningsManager: LearningsManager?

    @State private var showPopover = false

    private var matchedRule: InferredRule? {
        guard let ruleId = suggestion.ruleId,
              let rules = learningsManager?.currentProfile?.inferredRules else { return nil }
        return rules.first { $0.id == ruleId }
    }

    private var hasContent: Bool {
        matchedRule != nil || !suggestion.reasoning.isEmpty
    }

    private var isRule: Bool {
        matchedRule != nil
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

                    Image(systemName: isRule ? "sparkles" : "brain")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(
                            showPopover
                                ? (isRule ? Color.orange : Color.purple)
                                : Color.secondary
                        )
                }
            }
            .buttonStyle(.plain)
            .help(isRule ? "View learned rule" : "View AI reasoning")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                LiquidGlassReasoningPopover(
                    suggestion: suggestion,
                    matchedRule: matchedRule
                )
            }
        }
    }
}

struct LiquidGlassReasoningPopover: View {
    let suggestion: FolderSuggestion
    let matchedRule: InferredRule?

    private var isRule: Bool {
        matchedRule != nil
    }

    private var accentColor: Color {
        isRule ? .orange : .purple
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: isRule ? "sparkles" : "brain")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(isRule ? "Learned Rule" : "AI Reasoning")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(.primary)

                    Text(suggestion.folderName.hasPrefix("/")
                         ? URL(fileURLWithPath: suggestion.folderName).lastPathComponent
                         : suggestion.folderName)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Spacer()
            }
            .padding(.bottom, 10)

            Divider()
                .opacity(0.4)
                .padding(.bottom, 10)

            if let rule = matchedRule {
                FormattedReasoningText(
                    text: rule.explanation,
                    font: .callout,
                    secondaryFont: .caption,
                    foregroundStyle: .primary
                )

                if !suggestion.reasoning.isEmpty {
                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
            } else {
                FormattedReasoningText(
                    text: suggestion.reasoning,
                    font: .callout,
                    secondaryFont: .caption,
                    foregroundStyle: .primary
                )
            }
        }
        .padding(14)
        .frame(minWidth: 240, maxWidth: 340)
    }
}

#Preview("Liquid Glass - AI Reasoning") {
    let suggestion = FolderSuggestion(
        folderName: "Documents",
        reasoning: "These files share a common PDF format and appear to be work-related documents that belong together."
    )
    LiquidGlassReasoningButton(suggestion: suggestion)
        .padding()
}

#Preview("Liquid Glass - Empty") {
    let suggestion = FolderSuggestion(folderName: "Misc")
    LiquidGlassReasoningButton(suggestion: suggestion)
        .padding()
}
