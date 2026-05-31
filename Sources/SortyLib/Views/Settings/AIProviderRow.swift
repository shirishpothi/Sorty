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
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    ProviderLogoView(provider: provider, size: 20)
                        .frame(width: 34, height: 34)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(provider.brandColor.opacity(isSelected ? 0.16 : 0.1))
                        )

                    VStack(alignment: .leading, spacing: 3) {
                        Text(provider.displayName)
                            .font(.subheadline.weight(isSelected ? .semibold : .medium))
                            .foregroundStyle(.primary)

                        Text(provider.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 6)

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(isSelected ? provider.brandColor : Color.secondary.opacity(0.45))
                        .accessibilityHidden(true)
                }

                HStack(spacing: 6) {
                    ForEach(provider.settingsBadges) { badge in
                        AIProviderTag(badge: badge)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 102, alignment: .topLeading)
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

private struct AIProviderSettingsBadge: Identifiable {
    let title: String
    let color: Color

    var id: String { title }
}

private struct AIProviderTag: View {
    let badge: AIProviderSettingsBadge

    var body: some View {
        Text(badge.title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(badge.color)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(badge.color.opacity(0.12), in: Capsule())
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

    fileprivate var settingsBadges: [AIProviderSettingsBadge] {
        switch self {
        case .openAI:
            return [
                AIProviderSettingsBadge(title: "Recommended", color: .green),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .githubCopilot:
            return [
                AIProviderSettingsBadge(title: "Subscription", color: .indigo),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .groq:
            return [
                AIProviderSettingsBadge(title: "Fast", color: .orange),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .openAICompatible:
            return [
                AIProviderSettingsBadge(title: "Custom", color: .blue),
                AIProviderSettingsBadge(title: "Endpoint", color: .teal)
            ]
        case .openRouter:
            return [
                AIProviderSettingsBadge(title: "Model choice", color: .purple),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .ollama:
            return [
                AIProviderSettingsBadge(title: "Local", color: .green),
                AIProviderSettingsBadge(title: "No key", color: .secondary)
            ]
        case .anthropic:
            return [
                AIProviderSettingsBadge(title: "Claude", color: .orange),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .gemini:
            return [
                AIProviderSettingsBadge(title: "Gemini", color: .cyan),
                AIProviderSettingsBadge(title: "Cloud", color: .blue)
            ]
        case .appleFoundationModel:
            return [
                AIProviderSettingsBadge(title: "On-device", color: .blue),
                AIProviderSettingsBadge(title: "No key", color: .secondary)
            ]
        }
    }
    
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
