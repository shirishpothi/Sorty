//
//  TroubleshootingSettingsView.swift
//  Sorty
//
//  Troubleshooting settings section
//

import SwiftUI

struct TroubleshootingSettingsView: View {
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var notificationSettings: NotificationSettingsManager
    @EnvironmentObject var appState: AppState
    
    @State private var cacheSize: String = "Calculating..."
    @State private var showingResetConfirmation = false
    @State private var showingDeleteDataConfirmation = false
    @EnvironmentObject var learningsManager: LearningsManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Cache
            SettingsCard(title: "Cache", icon: "internaldrive", color: .orange) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Cache Size")
                            .font(.subheadline)
                        Spacer()
                        Text(cacheSize)
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }
                    
                    Button {
                        clearCache()
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Clear")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    .tint(.orange)
                }
            }
            .animatedAppearance(delay: 0.05)
            .onAppear {
                calculateCacheSize()
            }

            // Data Management
            SettingsCard(title: "Learnings Data", icon: "brain.head.profile", color: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Delete all recorded organization patterns, preferences, and personalizations.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showingDeleteDataConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "trash")
                            Text("Delete All Learning Data")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    .tint(.purple)
                }
            }
            .animatedAppearance(delay: 0.08)
            .alert("Delete All Learning Data?", isPresented: $showingDeleteDataConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        let didClear = await learningsManager.clearAllData()
                        if didClear {
                            HapticFeedbackManager.shared.success()
                        } else {
                            HapticFeedbackManager.shared.error()
                        }
                    }
                }
            } message: {
                Text("This will permanently delete all your learning data. This cannot be undone.")
            }
            
            // Reset Settings
            SettingsCard(title: "Reset", icon: "arrow.counterclockwise", color: .red) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reset all preferences to default values. This cannot be undone.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Button {
                        showingResetConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: "arrow.counterclockwise")
                            Text("Reset All Settings")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.onboardingPill)
                    .tint(.red)
                }
            }
            .animatedAppearance(delay: 0.1)
            .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllSettings()
                }
            } message: {
                Text("This will completely reset Sorty to its initial state, clearing all settings, history, and learnings. You'll go through onboarding again. This cannot be undone.")
            }
            
            // Common Issues section added for better Help integration
            SettingsCard(title: "Common Issues", icon: "lightbulb", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    TroubleshootingRow(
                        title: "AI takes too long?",
                        description: "Check your internet connection or try a faster model like GPT-5-mini in AI Provider settings."
                    )
                    TroubleshootingRow(
                        title: "Files not moving?",
                        description: "Ensure Sorty has Full Disk Access in System Settings -> Privacy & Security."
                    )
                    TroubleshootingRow(
                        title: "Wrong categorization?",
                        description: "Try turning off Fast Mode in Organization Controls to let the AI read file content."
                    )
                }
            }
            .animatedAppearance(delay: 0.15)
        }
    }
    
    private func calculateCacheSize() {
        Task {
            let size = await getCacheSizeAsync()
            await MainActor.run {
                cacheSize = formatBytes(size)
            }
        }
    }
    
    private func getCacheSizeAsync() async -> Int64 {
        var totalSize: Int64 = 0
        let fileManager = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        
        // Sorty-specific caches directory
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let sortyCaches = cachesURL.appendingPathComponent(bundleId)
            if fileManager.fileExists(atPath: sortyCaches.path) {
                totalSize += directorySize(at: sortyCaches)
            }
        }
        
        // App support directory for Sorty
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sortySupport = appSupportURL.appendingPathComponent("Sorty")
            if fileManager.fileExists(atPath: sortySupport.path) {
                totalSize += directorySize(at: sortySupport)
            }
        }
        
        return totalSize
    }
    
    private func directorySize(at url: URL) -> Int64 {
        let fileManager = FileManager.default
        var size: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        
        for case let fileURL as URL in enumerator {
            do {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
                if resourceValues.isDirectory == false {
                    size += Int64(resourceValues.fileSize ?? 0)
                }
            } catch {
                // Skip files we can't access
            }
        }
        
        return size
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
    
    private func clearCache() {
        let fileManager = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        
        // Clear only Sorty-specific caches directory (not the entire Mac cache)
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let sortyCaches = cachesURL.appendingPathComponent(bundleId)
            try? fileManager.removeItem(at: sortyCaches)
            try? fileManager.createDirectory(at: sortyCaches, withIntermediateDirectories: true)
        }
        
        // Clear Sorty data in app support (preserving the directory structure)
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sortySupport = appSupportURL.appendingPathComponent("Sorty")
            // Only clear cache subdirectory, not user data
            let cacheDir = sortySupport.appendingPathComponent("Cache")
            try? fileManager.removeItem(at: cacheDir)
        }
        
        // Recalculate size
        calculateCacheSize()
    }
    
    private func resetAllSettings() {
        // Reset AI config
        viewModel.config = .default
        
        // Reset notification settings
        notificationSettings.reset()
        
        // Clear ALL user defaults for this app
        let defaults = UserDefaults.standard
        let domain = Bundle.main.bundleIdentifier ?? ""
        defaults.removePersistentDomain(forName: domain)
        defaults.synchronize()
        
        // Clear app support data (learnings, history, etc.)
        let fileManager = FileManager.default
        if let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let sortySupport = appSupportURL.appendingPathComponent("Sorty")
            try? fileManager.removeItem(at: sortySupport)
        }
        
        // Clear Sorty caches
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            let sortyCaches = cachesURL.appendingPathComponent(bundleId)
            try? fileManager.removeItem(at: sortyCaches)
        }
        
        // Reset onboarding state AND version tracking to trigger fresh start
        defaults.set(false, forKey: "hasCompletedOnboarding")
        defaults.removeObject(forKey: "lastLaunchedVersion")
        defaults.synchronize()
        
        HapticFeedbackManager.shared.success()
        
        // Take user to onboarding screen immediately
        withAnimation(.spring()) {
            appState.hasCompletedOnboarding = false
        }
    }
}

// MARK: - Components

private struct TroubleshootingRow: View {
    let title: String
    let description: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.weight(.medium))
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    TroubleshootingSettingsView()
        .environmentObject(SettingsViewModel())
        .frame(width: 500, height: 300)
}
