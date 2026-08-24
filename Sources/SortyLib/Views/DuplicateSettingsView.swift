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
                    .systemLiquidGlassButton()
                    .help("Reset to Defaults")
                    .accessibilityLabel("Reset to Defaults")
                    
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .buttonStyle(.sortyPrimary(size: .small))
                    .systemLiquidGlassBackground(cornerRadius: 999)
                    .keyboardShortcut(.return)
                }
            }
            .padding(.horizontal, SortyDesignSystem.Spacing.xl)
            .padding(.vertical, SortyDesignSystem.Spacing.lg)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xl) {
                    SettingsCard(
                        title: "Cleanup Preference",
                        icon: "checkmark.circle",
                        color: SortyDesignSystem.Colors.primary
                    ) {
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
                                            .symbolReplaceTransition(animationValue: isSelected)

                                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxxs) {
                                            Text(strategy.displayName)
                                                .font(SortyDesignSystem.Typography.body(weight: .medium))
                                                .foregroundStyle(SortyDesignSystem.Colors.textPrimary)
                                            Text(LocalizedStringKey(strategy.description))
                                                .font(SortyDesignSystem.Typography.caption2())
                                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                        }

                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, SortyDesignSystem.Spacing.md)
                                    .padding(.vertical, SortyDesignSystem.Spacing.sm)
                                    .systemLiquidGlassBackground(
                                        cornerRadius: SortyDesignSystem.Radius.medium
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

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
