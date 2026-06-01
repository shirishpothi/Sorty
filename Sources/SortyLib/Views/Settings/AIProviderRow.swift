//
//  AIProviderRow.swift
//  Sorty
//
//  AI Provider selection row component
//

import SwiftUI

struct AIProviderRow: View {
    let provider: AIProvider
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false
    
    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                ProviderLogoView(provider: provider, size: 18)
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(provider.brandColor.opacity(isSelected ? 0.16 : 0.1))
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)

                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(isSelected ? provider.brandColor : Color.secondary.opacity(0.45))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? provider.brandColor.opacity(0.08) : (isHovered ? Color.primary.opacity(0.045) : Color.primary.opacity(0.025)))
            )
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? provider.brandColor.opacity(0.35) : Color.secondary.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .minimumHitTarget()
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isHovered)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isSelected)
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityHint("Selects \(provider.displayName) as the AI provider")
        .help("Use \(provider.displayName)")
    }
}

// MARK: - AI Provider Extensions

extension AIProvider {
    var iconName: String {
        switch self {
        case .openAI:
            return "circle.hexagongrid.fill"
        case .anthropic:
            return "sparkles"
        case .groq:
            return "bolt.fill"
        case .ollama:
            return "cube.fill"
        case .githubCopilot:
            return "person.badge.key.fill"
        case .appleFoundationModel:
            return "apple.logo"
        case .openAICompatible:
            return "network"
        case .openRouter:
            return "arrow.triangle.2.circlepath"
        case .gemini:
            return "diamond.fill"
        }
    }

    // brandColor is now defined canonically in AIProvider (AIConfig.swift)

    var description: String {
        switch self {
        case .openAI:
            return "GPT-5.2, GPT-5 mini, and more"
        case .anthropic:
            return "Claude 4.6 Sonnet, Claude 4.6 Opus, and more"
        case .groq:
            return "Ultra-fast inference provider"
        case .ollama:
            return "Local models on your machine"
        case .githubCopilot:
            return "Use your Copilot subscription"
        case .appleFoundationModel:
            return "On-device Apple Foundation Models"
        case .openAICompatible:
            return "Any OpenAI-compatible API"
        case .openRouter:
            return "Choose from the largest selection of providers"
        case .gemini:
            return "Google's Gemini models"
        }
    }
}
