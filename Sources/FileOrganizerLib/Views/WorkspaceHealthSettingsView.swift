//
//  WorkspaceHealthSettingsView.swift
//  FileOrganizer
//
//  Configuration interface for Workspace Health
//

import SwiftUI

struct WorkspaceHealthSettingsView: View {
    @ObservedObject var healthManager: WorkspaceHealthManager
    @Environment(\.dismiss) var dismiss
    
    // Local state for editing
    @State private var config: WorkspaceHealthConfig
    
    init(healthManager: WorkspaceHealthManager) {
        self.healthManager = healthManager
        _config = State(initialValue: healthManager.config)
    }
    
    var body: some View {
        Form {
            Section("Thresholds") {
                VStack(alignment: .leading) {
                    Text("Large File Threshold: \(ByteCountFormatter.string(fromByteCount: config.largeFileSizeThreshold, countStyle: .file))")
                    Slider(
                        value: Binding(
                            get: { Double(config.largeFileSizeThreshold) },
                            set: { config.largeFileSizeThreshold = Int64($0) }
                        ),
                        in: 10_000_000...1_000_000_000,
                        step: 10_000_000
                    ) {
                        Text("Large File Threshold")
                    } minimumValueLabel: {
                        Text("10MB")
                    } maximumValueLabel: {
                        Text("1GB")
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Old File Threshold: \(Int(config.oldFileThreshold / 86400)) days")
                    Slider(
                        value: Binding(
                            get: { config.oldFileThreshold / 86400 },
                            set: { config.oldFileThreshold = $0 * 86400 }
                        ),
                        in: 30...730,
                        step: 30
                    ) {
                        Text("Old File Threshold")
                    } minimumValueLabel: {
                        Text("1m")
                    } maximumValueLabel: {
                        Text("2y")
                    }
                }
                
                VStack(alignment: .leading) {
                    Text("Download Clutter: \(Int(config.downloadClutterThreshold / 86400)) days")
                    Slider(
                        value: Binding(
                            get: { config.downloadClutterThreshold / 86400 },
                            set: { config.downloadClutterThreshold = $0 * 86400 }
                        ),
                        in: 7...90,
                        step: 7
                    ) {
                        Text("Download Clutter Threshold")
                    } minimumValueLabel: {
                        Text("1w")
                    } maximumValueLabel: {
                        Text("3m")
                    }
                }
            }
            
            Section("Enabled Checks") {
                // Group checks by type/category if possible, or just list them
                ForEach(CleanupOpportunity.OpportunityType.allCases, id: \.self) { type in
                    Toggle(isOn: Binding(
                        get: { config.enabledChecks.contains(type) },
                        set: { isEnabled in
                            if isEnabled {
                                config.enabledChecks.insert(type)
                            } else {
                                config.enabledChecks.remove(type)
                            }
                        }
                    )) {
                        HStack {
                            Image(systemName: type.icon)
                                .foregroundColor(type.color)
                                .frame(width: 20)
                            Text(type.rawValue)
                        }
                    }
                }
            }
            
            Section("Ignored Paths") {
                List {
                    ForEach(config.ignoredPaths, id: \.self) { path in
                        Text(path)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .onDelete { indexSet in
                        config.ignoredPaths.remove(atOffsets: indexSet)
                    }
                    
                    if config.ignoredPaths.isEmpty {
                        Text("No ignored paths")
                            .foregroundColor(.secondary)
                            .italic()
                    }
                }
                
                Button("Add Ignored Path...") {
                    let panel = NSOpenPanel()
                    panel.canChooseFiles = false
                    panel.canChooseDirectories = true
                    panel.allowsMultipleSelection = true
                    
                    if panel.runModal() == .OK {
                        for url in panel.urls {
                            if !config.ignoredPaths.contains(url.path) {
                                config.ignoredPaths.append(url.path)
                            }
                        }
                    }
                }
            }
            
            /*
            Section {
                Button("Reset to Defaults") {
                    config = WorkspaceHealthConfig()
                }
                .foregroundColor(.red)
            }
             */
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    healthManager.updateConfig(config)
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            
            ToolbarItem(placement: .destructiveAction) {
                Button("Reset Defaults") {
                    config = WorkspaceHealthConfig()
                }
            }
        }
    }
}
