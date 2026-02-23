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
    
    @State private var isHovered = false
    
    var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.selection()
            action()
        }) {
            HStack(spacing: 12) {
                // Provider logo
                ProviderLogoView(provider: provider, size: 16)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(isSelected ? provider.brandColor.opacity(0.1) : Color.secondary.opacity(0.1))
                    )
                
                // Provider name and description
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName)
                        .font(.subheadline.weight(isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? .primary : .secondary)
                    
                    Text(provider.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()
                
                // Selection indicator
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(provider.brandColor)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? provider.brandColor.opacity(0.05) : (isHovered ? Color.secondary.opacity(0.05) : Color.clear))
            )
            .contentShape(Rectangle())
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? provider.brandColor.opacity(0.2) : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
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
            return "On-device Apple Intelligence"
        case .openAICompatible:
            return "Any OpenAI-compatible API"
        case .openRouter:
            return "Choose from the largest selection of providers"
        case .gemini:
            return "Google's Gemini models"
        }
    }
}