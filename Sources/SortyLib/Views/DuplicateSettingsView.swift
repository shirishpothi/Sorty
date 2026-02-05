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
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Duplicate Detection Settings")
                        .font(.title3.bold())
                    Text("Configure how Sorty identifies and handles identical files.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                
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
            .padding(24)
            .background(.bar)
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    
                    // Comparison Strategy
                    SettingsSection(title: "Matching Strategy", icon: "doc.text.magnifyingglass") {
                        VStack(alignment: .leading, spacing: 16) {
                            Picker("Comparison Method:", selection: $settingsManager.settings.comparisonMethod) {
                                ForEach(ComparisonMethod.allCases, id: \.self) { method in
                                    VStack(alignment: .leading) {
                                        Text(method.displayName)
                                        Text(method.description)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    .tag(method)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            
                            Divider()
                            
                            // Auto start
                            Toggle("Auto-start scan when opening Duplicates view", isOn: $settingsManager.settings.autoStartScan)
                                .font(.subheadline)
                        }
                    }

                    // Scan Filters
                    SettingsSection(title: "Scan Filters", icon: "line.3.horizontal.decrease.circle") {
                        VStack(alignment: .leading, spacing: 20) {
                            // Min file size
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text("Minimum File Size")
                                        .font(.subheadline.weight(.medium))
                                    Spacer()
                                    Text(minSizeMB == 0 ? "No minimum" : String(format: "%.1f MB", minSizeMB))
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $minSizeMB, in: 0...500, step: 0.5)
                            }
                            
                            HStack(spacing: 20) {
                                // Scan depth
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Scan Depth")
                                        .font(.subheadline.weight(.medium))
                                    Picker("", selection: $settingsManager.settings.maxScanDepth) {
                                        Text("Unlimited").tag(-1)
                                        Text("1 Level").tag(1)
                                        Text("3 Levels").tag(3)
                                        Text("5 Levels").tag(5)
                                    }
                                    .labelsHidden()
                                    .frame(maxWidth: 150)
                                }
                                
                                Spacer()
                            }
                            
                            VStack(alignment: .leading, spacing: 12) {
                                SettingsInput(label: "Include Extensions", text: $includeExtensionsText, placeholder: "jpg, png, pdf (leave empty for all)")
                                SettingsInput(label: "Exclude Extensions", text: $excludeExtensionsText, placeholder: ".DS_Store, .localized, .lnk")
                            }
                        }
                    }
                    
                    // Bulk Cleanup
                    SettingsSection(title: "Bulk Cleanup Rules", icon: "trash.circle") {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("When using 'Cleanup All', which file should be kept?")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Picker("", selection: $settingsManager.settings.defaultKeepStrategy) {
                                ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                                    HStack {
                                        Text(strategy.displayName)
                                        Spacer()
                                        Text(strategy.description)
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(strategy)
                                }
                            }
                            .pickerStyle(.radioGroup)
                            
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Toggle("Enable Safe Deletion", isOn: $settingsManager.settings.enableSafeDeletion)
                                    .font(.subheadline.weight(.medium))
                                
                                Text(settingsManager.settings.enableSafeDeletion ? "Files are moved to a temporary recovery zone and can be restored from History." : "⚠️ Warning: Files will be permanently removed from disk immediately.")
                                    .font(.caption)
                                    .foregroundColor(settingsManager.settings.enableSafeDeletion ? .secondary : .orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                    
                    // Semantic Detection
                    SettingsSection(title: "AI-Powered Matching", icon: "sparkles") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Semantic Matching", isOn: $settingsManager.settings.includeSemanticDuplicates)
                                .font(.subheadline.weight(.medium))
                            
                            if settingsManager.settings.includeSemanticDuplicates {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text("Similarity Threshold")
                                        Spacer()
                                        Text(String(format: "%.0f%%", settingsManager.settings.semanticSimilarityThreshold * 100))
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $settingsManager.settings.semanticSimilarityThreshold, in: 0.7...1.0, step: 0.05)
                                    
                                    Text("Used to find visually or contextually similar files even if binary data differs (e.g., resized images).")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .padding(.leading, 24)
                                .transition(.move(edge: .top).combined(with: .opacity))
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .frame(width: 600, height: 750)
        .background(Color(NSColor.windowBackgroundColor))
        .animation(.sortySpringStandard, value: settingsManager.settings.includeSemanticDuplicates)
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
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundStyle(Color.accentColor)
                Text(title)
                    .font(.headline)
            }
            
            content
                .padding(16)
                .background(Color.primary.opacity(0.03))
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.05), lineWidth: 1)
                )
        }
    }
}

struct SettingsInput: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.1), lineWidth: 1)
                )
        }
    }
}

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
