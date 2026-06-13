//
//  DuplicateSettingsView.swift
//  Sorty
//
//  UI for configuring duplicate detection settings
//

import SwiftUI

struct DuplicateSettingsView: View {
    @ObservedObject var settingsManager: DuplicateSettingsManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SortyDesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxs) {
                    Text("Duplicate Detection")
                        .font(SortyDesignSystem.Typography.title3())
                    Text("Reliable defaults, with only the cleanup choice exposed.")
                        .font(SortyDesignSystem.Typography.subheadline())
                        .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: SortyDesignSystem.Spacing.md) {
                    Button(action: {
                        HapticFeedbackManager.shared.tap()
                        settingsManager.reset()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                    }
                    .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                    .help("Reset to Defaults")
                    .accessibilityLabel("Reset to Defaults")
                    
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .keyboardShortcut(.return)
                }
            }
            .padding(.horizontal, SortyDesignSystem.Spacing.xl)
            .padding(.vertical, SortyDesignSystem.Spacing.lg)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xl) {
                    SettingsSection(title: "Cleanup Preference", icon: "checkmark.circle") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
                            Text("When cleaning a duplicate group, keep:")
                                .font(SortyDesignSystem.Typography.subheadline())
                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                            
                            ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                                let isSelected = settingsManager.settings.defaultKeepStrategy == strategy

                                Button {
                                    guard settingsManager.settings.defaultKeepStrategy != strategy else { return }
                                    HapticFeedbackManager.shared.selection()
                                    settingsManager.settings.defaultKeepStrategy = strategy
                                } label: {
                                    HStack(alignment: .center, spacing: SortyDesignSystem.Spacing.md) {
                                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(isSelected ? SortyDesignSystem.Colors.primary : SortyDesignSystem.Colors.textTertiary)

                                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxxs) {
                                            Text(strategy.displayName)
                                                .font(SortyDesignSystem.Typography.body(weight: .medium))
                                                .foregroundStyle(SortyDesignSystem.Colors.textPrimary)
                                            Text(strategy.description)
                                                .font(SortyDesignSystem.Typography.caption2())
                                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, SortyDesignSystem.Spacing.md)
                                    .padding(.vertical, SortyDesignSystem.Spacing.sm)
                                    .background(
                                        RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.medium)
                                            .fill(isSelected ? SortyDesignSystem.Colors.primary.opacity(0.12) : SortyDesignSystem.Colors.backgroundTertiary.opacity(0.25))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.medium)
                                            .stroke(isSelected ? SortyDesignSystem.Colors.primary.opacity(0.35) : SortyDesignSystem.Colors.glassBorder, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(strategy.displayName)
                                .accessibilityValue(isSelected ? "Selected" : "Not selected")
                            }

                            Divider()

                            VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.sm) {
                                Text("Describe cleanup preference")
                                    .font(SortyDesignSystem.Typography.body(weight: .medium))
                                    .foregroundStyle(SortyDesignSystem.Colors.textPrimary)

                                Text("Sorty uses this as a rule hint when choosing the default file to keep. You can still change the kept file in each group.")
                                    .font(SortyDesignSystem.Typography.caption2())
                                    .foregroundStyle(SortyDesignSystem.Colors.textSecondary)

                                TextField(
                                    "Example: Keep files in Originals, prefer highest resolution, otherwise newest",
                                    text: $settingsManager.settings.cleanupPreferencePrompt,
                                    axis: .vertical
                                )
                                .textFieldStyle(.plain)
                                .lineLimit(3...5)
                                .padding(SortyDesignSystem.Spacing.md)
                                .background(
                                    RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.medium)
                                        .fill(SortyDesignSystem.Colors.backgroundTertiary.opacity(0.28))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.medium)
                                        .stroke(SortyDesignSystem.Colors.glassBorder, lineWidth: 1)
                                )
                                .accessibilityLabel("Cleanup preference")
                            }
                            
                        }
                    }

                }
                .padding(SortyDesignSystem.Spacing.xl)
            }
        }
        .frame(width: 620, height: 520)
        .background(SortyDesignSystem.Colors.backgroundPrimary)
    }
    
    private func saveAndDismiss() {
        HapticFeedbackManager.shared.light()
        settingsManager.save()
        dismiss()
    }
}

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
            HStack(spacing: SortyDesignSystem.Spacing.sm) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(SortyDesignSystem.Colors.primary)
                    .frame(width: 24, height: 24)
                    .background(SortyDesignSystem.Colors.primary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                
                Text(title)
                    .font(SortyDesignSystem.Typography.headline())
            }
            
            content
                .padding(SortyDesignSystem.Spacing.md)
                .systemLiquidGlassBackground(cornerRadius: SortyDesignSystem.Radius.large)
        }
    }
}

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
