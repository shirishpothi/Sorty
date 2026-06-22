//
//  SortyCard.swift
//  Sorty
//
//  Reusable card component based on design system
//

import SwiftUI

/// A reusable card component for Sorty that provides consistent styling
public struct SortyCard<Content: View>: View {
    let title: String?
    let icon: String?
    let iconColor: Color
    let style: SortyDesignSystem.CardStyles.CardStyle
    @ViewBuilder let content: Content
    
    /// Creates a new SortyCard
    /// - Parameters:
    ///   - title: Optional card title
    ///   - icon: Optional icon system name
    ///   - iconColor: Color for the icon (defaults to accent color)
    ///   - style: Card style from design system (defaults to .standard)
    ///   - content: Card content
    public init(
        title: String? = nil,
        icon: String? = nil,
        iconColor: Color = .accentColor,
        style: SortyDesignSystem.CardStyles.CardStyle = SortyDesignSystem.CardStyles.standard,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.iconColor = iconColor
        self.style = style
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.md) {
            // Header with icon and title
            if let title = title {
                HStack(spacing: SortyDesignSystem.Spacing.sm) {
                    if let icon = icon {
                        Image(systemName: icon)
                            .font(.system(size: SortyDesignSystem.Sizing.iconSmall))
                            .foregroundStyle(iconColor)
                    }
                    
                    Text(title)
                        .font(SortyDesignSystem.Typography.subheadline(weight: .semibold))
                        .foregroundColor(.secondary)
                    
                    Spacer()
                }
            }
            
            // Content
            content
        }
        .sortyCardStyle(style)
    }
}

/// A card that acts as a navigation button
public struct SortyNavigationCard: View {
    let title: String
    let description: String
    let icon: String
    let color: Color
    let action: () -> Void
    
    @State private var isHovered = false
    
    public init(
        title: String,
        description: String,
        icon: String,
        color: Color,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.description = description
        self.icon = icon
        self.color = color
        self.action = action
    }
    
    public var body: some View {
        Button(action: {
            HapticFeedbackManager.shared.tap()
            action()
        }) {
            HStack(spacing: SortyDesignSystem.Spacing.lg) {
                // Icon container
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(
                        width: SortyDesignSystem.Sizing.iconXXLarge,
                        height: SortyDesignSystem.Sizing.iconXXLarge
                    )
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.medium))
                
                // Text content
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxs) {
                    Text(title)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                // Chevron
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(SortyDesignSystem.Spacing.md)
            .background(isHovered ? Color.primary.opacity(0.05) : Color.clear)
            .background(.ultraThinMaterial)
            .contentShape(Rectangle())
            .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large))
            .overlay(
                RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// A card for displaying workflow steps
public struct SortyWorkflowCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    public init(
        title: String,
        icon: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.md) {
            HStack(spacing: SortyDesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: SortyDesignSystem.Sizing.iconSmall))
                    .foregroundStyle(.secondary)
                
                Text(title)
                    .font(SortyDesignSystem.Typography.subheadline(weight: .semibold))
                    .foregroundColor(.secondary)
                
                Spacer()
            }
            
            content
        }
        .padding(SortyDesignSystem.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large))
        .overlay(
            RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
    }
}

// MARK: - Preview
#Preview("SortyCard Variants") {
    ScrollView {
        VStack(spacing: SortyDesignSystem.Spacing.xl) {
            // Standard card with title and icon
            SortyCard(
                title: "Organization Settings",
                icon: "folder.badge.gearshape",
                iconColor: .purple
            ) {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.sm) {
                    Text("Configure how files are organized")
                        .font(.body)
                    Toggle("Enable Smart Rename", isOn: .constant(true))
                }
            }
            
            // Filled card
            SortyCard(
                title: "API Configuration",
                icon: "key",
                iconColor: .orange,
                style: SortyDesignSystem.CardStyles.filled
            ) {
                Text("Enter your API credentials")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            // Subtle card
            SortyCard(
                title: "Quick Settings",
                icon: "bolt",
                iconColor: .yellow,
                style: SortyDesignSystem.CardStyles.subtle
            ) {
                HStack {
                    Text("Fast Mode")
                    Spacer()
                    Toggle("", isOn: .constant(false))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            
            // Card without header
            SortyCard {
                Text("This card has no title or icon, just content.")
                    .font(.body)
            }
            
            // Navigation card
            SortyNavigationCard(
                title: "Storage Locations",
                description: "Add external destinations for files",
                icon: "externaldrive",
                color: .purple
            ) {
                print("Tapped")
            }
            
            // Workflow card
            SortyWorkflowCard(
                title: "Instructions",
                icon: "text.bubble"
            ) {
                Text("Add custom instructions for Sorty")
                    .font(.body)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
    }
    .frame(width: 500, height: 700)
}
