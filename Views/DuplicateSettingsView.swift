//
//  DuplicateSettingsView.swift
//  FileOrganizer
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
            // Header
            HStack {
                Text("Duplicate Detection Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                Button("Reset to Defaults") {
                    settingsManager.reset()
                    syncFromSettings()
                }
                .buttonStyle(.bordered)
                
                Button("Done") {
                    saveAndDismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Scan Options
                    GroupBox("Scan Options") {
                        VStack(alignment: .leading, spacing: 16) {
                            // Min file size
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Minimum File Size:")
                                    Spacer()
                                    Text(minSizeMB == 0 ? "No minimum" : String(format: "%.1f MB", minSizeMB))
                                        .foregroundColor(.secondary)
                                }
                                Slider(value: $minSizeMB, in: 0...100, step: 0.5)
                            }
                            
                            // Scan depth
                            Picker("Scan Depth:", selection: $settingsManager.settings.maxScanDepth) {
                                Text("Unlimited").tag(-1)
                                Text("1 Level").tag(1)
                                Text("2 Levels").tag(2)
                                Text("3 Levels").tag(3)
                                Text("5 Levels").tag(5)
                                Text("10 Levels").tag(10)
                            }
                            
                            // Auto start
                            Toggle("Auto-start scan when opening Duplicates view", isOn: $settingsManager.settings.autoStartScan)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // File Type Filters
                    GroupBox("File Type Filters") {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Include Extensions (empty = all):")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("e.g., jpg, png, pdf", text: $includeExtensionsText)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Exclude Extensions:")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                TextField("e.g., .DS_Store, .localized", text: $excludeExtensionsText)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Keep Strategy
                    GroupBox("Default Keep Strategy") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("When bulk deleting, keep:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $settingsManager.settings.defaultKeepStrategy) {
                                ForEach(KeepStrategy.allCases, id: \.self) { strategy in
                                    HStack {
                                        Text(strategy.displayName)
                                        Text("- \(strategy.description)")
                                            .foregroundColor(.secondary)
                                    }
                                    .tag(strategy)
                                }
                            }
                            .pickerStyle(.radioGroup)
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Deletion Options
                    GroupBox("Deletion Options") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Enable Safe Deletion (move to trash with restore option)", isOn: $settingsManager.settings.enableSafeDeletion)
                            
                            if settingsManager.settings.enableSafeDeletion {
                                Text("Files can be restored from History after deletion")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                Text("⚠️ Files will be permanently deleted")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Semantic Duplicates
                    GroupBox("Semantic Duplicates") {
                        VStack(alignment: .leading, spacing: 12) {
                            Toggle("Include similar files (not just exact matches)", isOn: $settingsManager.settings.includeSemanticDuplicates)
                            
                            if settingsManager.settings.includeSemanticDuplicates {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Text("Similarity Threshold:")
                                        Spacer()
                                        Text(String(format: "%.0f%%", settingsManager.settings.semanticSimilarityThreshold * 100))
                                            .foregroundColor(.secondary)
                                    }
                                    Slider(value: $settingsManager.settings.semanticSimilarityThreshold, in: 0.7...1.0, step: 0.05)
                                }
                                
                                Text("Higher threshold = stricter matching")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
                .padding()
            }
        }
        .frame(width: 550, height: 650)
    }
    
    private func syncFromSettings() {
        minSizeMB = Double(settingsManager.settings.minFileSize) / (1024 * 1024)
        includeExtensionsText = settingsManager.settings.includeExtensions.joined(separator: ", ")
        excludeExtensionsText = settingsManager.settings.excludeExtensions.joined(separator: ", ")
    }
    
    private func saveAndDismiss() {
        // Convert min size from MB to bytes
        settingsManager.settings.minFileSize = Int64(minSizeMB * 1024 * 1024)
        
        // Parse extension lists
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

#Preview {
    DuplicateSettingsView(settingsManager: DuplicateSettingsManager())
}
