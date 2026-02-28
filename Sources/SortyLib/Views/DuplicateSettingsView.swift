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
    
    @State private var minSizeMB: Double = 0
    @State private var includeExtensionsText: String = ""
    @State private var excludeExtensionsText: String = ""
    
    init(settingsManager: DuplicateSettingsManager) {
        self.settingsManager = settingsManager
        _minSizeMB = State(initialValue: Double(settingsManager.settings.minFileSize) / (1024 * 1024))
        _includeExtensionsText = State(initialValue: settingsManager.settings.includeExtensions.joined(separator: ", "))
        _excludeExtensionsText = State(initialValue: settingsManager.settings.excludeExtensions.joined(separator: ", "))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // New Header
            HStack(spacing: SortyDesignSystem.Spacing.lg) {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxs) {
                    Text("Duplicate Detection Settings")
                        .font(SortyDesignSystem.Typography.title3())
                    Text("Configure how Sorty identifies and handles identical files.")
                        .font(SortyDesignSystem.Typography.subheadline())
                        .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                }
                
                Spacer()
                
                HStack(spacing: SortyDesignSystem.Spacing.md) {
                    Button(action: {
                        settingsManager.reset()
                        syncFromSettings()
                    }) {
                        Image(systemName: "arrow.counterclockwise")
                            .help("Reset to Defaults")
                    }
                    .buttonStyle(.onboardingPill(isSecondary: true, size: .small))
                    
                    Button("Done") {
                        saveAndDismiss()
                    }
                    .buttonStyle(.onboardingPill(size: .small))
                    .keyboardShortcut(.return)
                }
            }
            .padding(SortyDesignSystem.Spacing.xxl)
            .background(.bar)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xxxl) {
                    
                    // Comparison Strategy
                    SettingsSection(title: "Matching Strategy", icon: "doc.text.magnifyingglass") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
                            Picker("Comparison Method:", selection: $settingsManager.settings.comparisonMethod) {
                                ForEach(ComparisonMethod.allCases, id: \.self) { method in
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(method.displayName)
                                            .font(SortyDesignSystem.Typography.body(weight: .medium))
                                        Text(method.description)
                                            .font(SortyDesignSystem.Typography.caption())
                                            .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                    }
                                    .tag(method)
                                    .padding(.vertical, 4)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            
                            Divider()
                                .opacity(0.5)
                            
                            // Auto start
                            Toggle("Auto-start scan when opening Duplicates view", isOn: $settingsManager.settings.autoStartScan)
                                .font(SortyDesignSystem.Typography.subheadline())
                        }
                    }

                    // Scan Filters
                    SettingsSection(title: "Scan Filters", icon: "line.3.horizontal.decrease.circle") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xl) {
                            // Min file size
                            VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.sm) {
                                HStack {
                                    Text("Minimum File Size")
                                        .font(SortyDesignSystem.Typography.subheadline(weight: .medium))
                                    Spacer()
                                    Text(minSizeMB == 0 ? "No minimum" : String(format: "%.1f MB", minSizeMB))
                                        .font(SortyDesignSystem.Typography.mono(size: SortyDesignSystem.Typography.sizeCaption))
                                        .foregroundStyle(SortyDesignSystem.Colors.primary)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 2)
                                        .background(SortyDesignSystem.Colors.primary.opacity(0.1))
                                        .clipShape(Capsule())
                                }
                                
                                VStack(spacing: SortyDesignSystem.Spacing.xxs) {
                                    Slider(value: $minSizeMB, in: 0...500, step: 0.5)
                                        .accentColor(SortyDesignSystem.Colors.primary)
                                    
                                    HStack {
                                        Text("0 MB")
                                        Spacer()
                                        Text("500 MB")
                                    }
                                    .font(SortyDesignSystem.Typography.caption2())
                                    .foregroundStyle(SortyDesignSystem.Colors.textTertiary)
                                }
                            }
                            
                            HStack(spacing: SortyDesignSystem.Spacing.xxxl) {
                                // Scan depth
                                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xs) {
                                    Text("Scan Depth")
                                        .font(SortyDesignSystem.Typography.subheadline(weight: .medium))
                                    Picker("", selection: $settingsManager.settings.maxScanDepth) {
                                        Text("Unlimited").tag(-1)
                                        Text("1 Level").tag(1)
                                        Text("3 Levels").tag(3)
                                        Text("5 Levels").tag(5)
                                    }
                                    .labelsHidden()
                                    .frame(width: 120)
                                }
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
                                SettingsInput(label: "Include Extensions", text: $includeExtensionsText, placeholder: "jpg, png, pdf (leave empty for all)")
                                SettingsInput(label: "Exclude Extensions", text: $excludeExtensionsText, placeholder: ".DS_Store, .localized, .lnk")
                            }
                        }
                    }
                    
                    // Bulk Cleanup
                    SettingsSection(title: "Bulk Cleanup Rules", icon: "trash.circle") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
                            Text("When using 'Cleanup All', which file should be kept?")
                                .font(SortyDesignSystem.Typography.subheadline())
                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                            
                            Picker("", selection: $settingsManager.settings.defaultKeepStrategy) {
                                ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                                    HStack {
                                        Text(strategy.displayName)
                                            .font(SortyDesignSystem.Typography.body(weight: .medium))
                                        Spacer()
                                        Text(strategy.description)
                                            .font(SortyDesignSystem.Typography.caption2())
                                            .foregroundStyle(SortyDesignSystem.Colors.textTertiary)
                                    }
                                    .tag(strategy)
                                    .padding(.vertical, 2)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            
                            Divider()
                                .opacity(0.5)
                            
                            VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.sm) {
                                Toggle("Enable Safe Deletion", isOn: $settingsManager.settings.enableSafeDeletion)
                                    .font(SortyDesignSystem.Typography.subheadline(weight: .medium))
                                
                                HStack(alignment: .top, spacing: SortyDesignSystem.Spacing.xs) {
                                    Image(systemName: settingsManager.settings.enableSafeDeletion ? "info.circle" : "exclamationmark.triangle")
                                        .font(.caption)
                                    
                                    Text(settingsManager.settings.enableSafeDeletion ? "Files are moved to a temporary recovery zone and can be restored from History." : "Warning: Files will be permanently removed from disk immediately.")
                                        .font(SortyDesignSystem.Typography.caption())
                                }
                                .foregroundStyle(settingsManager.settings.enableSafeDeletion ? SortyDesignSystem.Colors.textSecondary : SortyDesignSystem.Colors.warning)
                                .padding(SortyDesignSystem.Spacing.sm)
                                .background(settingsManager.settings.enableSafeDeletion ? SortyDesignSystem.Colors.overlayLight : SortyDesignSystem.Colors.warning.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.small))
                            }
                        }
                    }
                    
                    // Semantic Detection
                    SettingsSection(title: "AI-Powered Matching", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.lg) {
                            Toggle("Enable Semantic Matching", isOn: $settingsManager.settings.includeSemanticDuplicates)
                                .font(SortyDesignSystem.Typography.subheadline(weight: .medium))

                            Text("Find near-duplicates even when file bytes differ, such as resized images, recompressed exports, or revised documents.")
                                .font(SortyDesignSystem.Typography.caption())
                                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                            
                            if settingsManager.settings.includeSemanticDuplicates {
                                VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.md) {
                                    HStack {
                                        Text("Similarity Threshold")
                                            .font(SortyDesignSystem.Typography.subheadline())
                                        Spacer()
                                        Text("\(semanticThresholdPercent)%")
                                            .font(SortyDesignSystem.Typography.mono(size: SortyDesignSystem.Typography.sizeCaption))
                                            .foregroundStyle(SortyDesignSystem.Colors.primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 2)
                                            .background(SortyDesignSystem.Colors.primary.opacity(0.1))
                                            .clipShape(Capsule())
                                    }

                                    Text(semanticThresholdGuidance)
                                        .font(SortyDesignSystem.Typography.caption())
                                        .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                    
                                    VStack(spacing: SortyDesignSystem.Spacing.xxs) {
                                        Slider(
                                            value: Binding(
                                                get: { settingsManager.settings.normalizedSemanticSimilarityThreshold },
                                                set: { newValue in
                                                    settingsManager.settings.semanticSimilarityThreshold = DuplicateSettings.clampedSemanticSimilarityThreshold(newValue)
                                                }
                                            ),
                                            in: DuplicateSettings.minSemanticSimilarityThreshold...DuplicateSettings.maxSemanticSimilarityThreshold,
                                            step: 0.05
                                        )
                                            .accentColor(SortyDesignSystem.Colors.primary)
                                        
                                        HStack {
                                            Text("Looser (70%)")
                                            Spacer()
                                            Text("Stricter (100%)")
                                        }
                                        .font(SortyDesignSystem.Typography.caption2())
                                        .foregroundStyle(SortyDesignSystem.Colors.textTertiary)
                                    }
                                    
                                    Text("Recommended: 90% for balanced precision and recall.")
                                        .font(SortyDesignSystem.Typography.caption())
                                        .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, SortyDesignSystem.Spacing.xxl)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(SortyDesignSystem.Spacing.xxl)
            }
        }
        .frame(width: 600, height: 750)
        .background(SortyDesignSystem.Colors.backgroundPrimary)
        .animation(.sortySpringStandard, value: settingsManager.settings.includeSemanticDuplicates)
    }

    private var semanticThresholdPercent: Int {
        Int((settingsManager.settings.normalizedSemanticSimilarityThreshold * 100).rounded())
    }

    private var semanticThresholdGuidance: String {
        let threshold = settingsManager.settings.normalizedSemanticSimilarityThreshold
        if threshold >= 0.98 {
            return "Very strict: keep only near-identical matches and minimize false positives."
        }
        if threshold >= 0.90 {
            return "Balanced: prioritize quality while still catching strong near-duplicates."
        }
        if threshold >= 0.80 {
            return "Moderate: include broader visual/contextual variants with some manual review."
        }
        return "Loose: maximize discovery of variants; review results carefully before cleanup."
    }
    
    private func syncFromSettings() {
        minSizeMB = Double(settingsManager.settings.minFileSize) / (1024 * 1024)
        includeExtensionsText = settingsManager.settings.includeExtensions.joined(separator: ", ")
        excludeExtensionsText = settingsManager.settings.excludeExtensions.joined(separator: ", ")
    }
    
    private func saveAndDismiss() {
        settingsManager.settings.minFileSize = Int64(minSizeMB * 1024 * 1024)
        
        settingsManager.settings.includeExtensions = includeExtensionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        settingsManager.settings.excludeExtensions = excludeExtensionsText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
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
                .padding(SortyDesignSystem.Spacing.lg)
                .background(SortyDesignSystem.Colors.backgroundSecondary.opacity(0.5))
                .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large))
                .overlay(
                    RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.large)
                        .stroke(SortyDesignSystem.Colors.glassBorder, lineWidth: 1)
                )
        }
    }
}

struct SettingsInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: SortyDesignSystem.Spacing.xs) {
            Text(label)
                .font(SortyDesignSystem.Typography.subheadline(weight: .medium))
                .foregroundStyle(SortyDesignSystem.Colors.textSecondary)
            
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(SortyDesignSystem.Spacing.sm)
                .background(SortyDesignSystem.Colors.backgroundTertiary)
                .clipShape(RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.small))
                .overlay(
                    RoundedRectangle(cornerRadius: SortyDesignSystem.Radius.small)
                        .stroke(SortyDesignSystem.Colors.glassBorder, lineWidth: 1)
                )
        }
    }
}

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
