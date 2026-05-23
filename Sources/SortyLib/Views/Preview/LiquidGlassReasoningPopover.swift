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
                Image(systemName: isRule ? "sparkles" : "brain")
                    .font(.caption2)
                    .foregroundStyle(
                        showPopover
                            ? (isRule ? Color.orange : Color.purple)
                            : .secondary
                    )
            }
            .buttonStyle(.plain)
            .help(isRule ? "View learned rule" : "View AI reasoning")
            .popover(isPresented: $showPopover, arrowEdge: .bottom) {
                LiquidGlassReasoningPopover(
                    suggestion: suggestion,
                    matchedRule: matchedRule
                )
                .systemLiquidGlassPopover(cornerRadius: 12)
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
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: isRule ? "sparkles" : "brain")
                    .font(.caption)
                    .foregroundStyle(accentColor)

                Text(isRule ? "Learned Rule" : "AI Reasoning")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)

                Spacer()

                Text(suggestion.folderName.hasPrefix("/")
                     ? URL(fileURLWithPath: suggestion.folderName).lastPathComponent
                     : suggestion.folderName)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            if let rule = matchedRule {
                FormattedReasoningText(
                    text: rule.explanation,
                    font: .callout,
                    secondaryFont: .caption,
                    foregroundStyle: .primary
                )

                if !suggestion.reasoning.isEmpty {
                    Text(FeatureFlags.privacyModeEnabled ? PrivacyPathMasker.redactedText(suggestion.reasoning) : suggestion.reasoning)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
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
        .padding(12)
        .frame(minWidth: 240, maxWidth: 340)
    }
}

struct RenameReasoningPopoverButton: View {
    let reason: String
    var help: String = "View why the filename was kept"

    @State private var showPopover = false

    var body: some View {
        Button {
            showPopover.toggle()
        } label: {
            Image(systemName: "brain")
                .font(.caption2)
                .foregroundStyle(showPopover ? Color.purple : Color.secondary)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel("AI reasoning")
        .accessibilityHint(help)
        .popover(isPresented: $showPopover, arrowEdge: .bottom) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)

                    Text("AI Reasoning")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.primary)

                    Spacer()
                }

                FormattedReasoningText(
                    text: FeatureFlags.privacyModeEnabled ? PrivacyPathMasker.redactedText(reason) : reason,
                    font: .callout,
                    secondaryFont: .caption,
                    foregroundStyle: .primary
                )
                .frame(maxWidth: 280, alignment: .leading)
            }
            .padding(12)
            .frame(width: 320)
            .systemLiquidGlassPopover(cornerRadius: 12)
        }
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
