//
//  RuleReasoningBadge.swift
//  Sorty
//
//  Compact badge showing AI reasoning or learned rule context for folder suggestions
//

import SwiftUI

struct RuleReasoningBadge: View {
    let suggestion: FolderSuggestion
    var learningsManager: LearningsManager?

    @State private var isExpanded = false

    private var matchedRule: InferredRule? {
        guard let ruleId = suggestion.ruleId,
              let rules = learningsManager?.currentProfile?.inferredRules else { return nil }
        return rules.first { $0.id == ruleId }
    }

    private var hasContent: Bool {
        matchedRule != nil || !suggestion.reasoning.isEmpty
    }

    var body: some View {
        if hasContent {
            VStack(alignment: .leading, spacing: 4) {
                badgePill
                if isExpanded {
                    expandedContent
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .accessibilityIdentifier("ruleReasoningBadge")
        }
    }

    @ViewBuilder
    private var badgePill: some View {
        Button {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.75)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                if matchedRule != nil {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(truncatedLabel)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .lineLimit(1)
                } else {
                    Image(systemName: "brain")
                        .font(.caption2)
                        .foregroundColor(.purple)
                    Text(truncatedLabel)
                        .font(.caption)
                        .foregroundColor(.purple)
                        .lineLimit(1)
                }

                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(matchedRule != nil ? Color.orange.opacity(0.1) : Color.purple.opacity(0.1))
            )
        }
        .buttonStyle(.plain)
        .help(matchedRule != nil ? "Learned Rule" : "AI Reasoning")
    }

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let rule = matchedRule {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Learned Rule")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }

                FormattedReasoningText(
                    text: rule.explanation,
                    font: .caption,
                    secondaryFont: .caption2,
                    foregroundStyle: .secondary,
                    showSectionIcons: false
                )

                if !suggestion.reasoning.isEmpty {
                    Text(suggestion.reasoning)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                }
            } else {
                FormattedReasoningText(
                    text: suggestion.reasoning,
                    font: .caption,
                    secondaryFont: .caption2,
                    foregroundStyle: .secondary,
                    showSectionIcons: false
                )
            }
        }
        .padding(8)
        .background(Color.secondary.opacity(0.05))
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
        )
    }

    private var truncatedLabel: String {
        if let rule = matchedRule {
            let text = rule.explanation
            return text.count > 40 ? String(text.prefix(40)) + "…" : text
        }
        let text = suggestion.reasoning
        return text.count > 40 ? String(text.prefix(40)) + "…" : text
    }
}

#Preview("Rule Reasoning - AI") {
    let suggestion = FolderSuggestion(
        folderName: "Documents",
        reasoning: "These files share a common PDF format and appear to be work-related documents"
    )
    RuleReasoningBadge(suggestion: suggestion)
        .padding()
}

#Preview("Rule Reasoning - Empty") {
    let suggestion = FolderSuggestion(folderName: "Misc")
    RuleReasoningBadge(suggestion: suggestion)
        .padding()
}
