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
            HStack(alignment: .center, spacing: 8) {
                ProviderLogoView(provider: provider, size: 17)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(provider.brandColor.opacity(isSelected ? 0.16 : 0.1))
                    )
                    .overlay(alignment: .bottomTrailing) {
                        if isSelected {
                            ZStack {
                                Circle()
                                    .fill(provider.brandColor)

                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                            .frame(width: 13, height: 13)
                            .offset(x: 2, y: 2)
                            .accessibilityHidden(true)
                        }
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.selectorTitle)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)

                    Text(provider.selectorDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.88)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
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
    var selectorTitle: String {
        switch self {
        case .githubCopilot:
            return "Copilot"
        case .openAICompatible:
            return "Compatible API"
        case .openRouter:
            return "OpenRouter"
        case .anthropic:
            return "Claude"
        case .appleFoundationModel:
            return "Apple"
        default:
            return displayName
        }
    }

    var selectorDescription: String {
        switch self {
        case .openAI:
            return "API key or ChatGPT"
        case .anthropic:
            return "Claude models"
        case .groq:
            return "Fast inference"
        case .ollama:
            return "Local models"
        case .githubCopilot:
            return "Subscription models"
        case .appleFoundationModel:
            return "On-device"
        case .openAICompatible:
            return "Custom endpoint"
        case .openRouter:
            return "Model router"
        case .gemini:
            return "Gemini models"
        }
    }

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
