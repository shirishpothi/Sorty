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

    private let defaultsDomain = "com.sorty.app"
    
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
                            
                        }
                    }

                    SettingsSection(title: "Defaults", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.md) {
                            Label("Exact and semantic matching", systemImage: "checkmark")
                            Label("Automatic scans with unlimited depth", systemImage: "checkmark")
                            Label("All file sizes, with common system files excluded", systemImage: "checkmark")
                            Label("Recoverable safe deletion", systemImage: "checkmark")
                        }
                        .font(SortyDesignSystem.Typography.caption())
                        .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                    }

                    SettingsSection(title: "Terminal Overrides", icon: "terminal") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.sm) {
                            Text("Advanced options stay available through macOS defaults. Restart Sorty after changing them.")
                                .font(SortyDesignSystem.Typography.caption())
                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)

                            DefaultsCommandRow(
                                title: "Minimum file size: 10 MB",
                                command: "defaults write \(defaultsDomain) duplicates.minimumFileSizeMB -float 10"
                            )
                            DefaultsCommandRow(
                                title: "Maximum scan depth: 3",
                                command: "defaults write \(defaultsDomain) duplicates.maximumScanDepth -int 3"
                            )
                            DefaultsCommandRow(
                                title: "Disable semantic matching",
                                command: "defaults write \(defaultsDomain) duplicates.semanticMatching -bool false"
                            )
                            DefaultsCommandRow(
                                title: "Semantic threshold: 95%",
                                command: "defaults write \(defaultsDomain) duplicates.semanticThreshold -float 0.95"
                            )
                            DefaultsCommandRow(
                                title: "Reset all advanced overrides",
                                command: [
                                    "comparisonMethod",
                                    "minimumFileSizeMB",
                                    "maximumScanDepth",
                                    "includeExtensions",
                                    "excludeExtensions",
                                    "autoStartScan",
                                    "semanticMatching",
                                    "semanticThreshold",
                                    "safeDeletion"
                                ]
                                .map { "defaults delete \(defaultsDomain) duplicates.\($0)" }
                                .joined(separator: " ; ")
                            )
                        }
                    }
                }
                .padding(SortyDesignSystem.Spacing.xl)
            }
        }
        .frame(width: 620, height: 640)
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

private struct DefaultsCommandRow: View {
    let title: String
    let command: String
    @State private var copied = false
    
    var body: some View {
        HStack(spacing: SortyDesignSystem.Spacing.sm) {
            VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxxs) {
                Text(title)
                    .font(SortyDesignSystem.Typography.caption())
                Text(command)
                    .font(.caption2.monospaced())
                    .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                    .lineLimit(1)
            }

            Spacer(minLength: SortyDesignSystem.Spacing.sm)

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                HapticFeedbackManager.shared.tap()
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
            }
            .buttonStyle(.plain)
            .frame(width: 28, height: 28)
            .contentShape(Rectangle())
            .accessibilityLabel("Copy \(title) command")
        }
        .padding(.horizontal, SortyDesignSystem.Spacing.sm)
        .padding(.vertical, SortyDesignSystem.Spacing.xs)
    }
}

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
