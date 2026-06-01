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
            SettingsCard(title: "Maintenance", icon: "wrench.and.screwdriver", color: .orange) {
                HStack(spacing: 10) {
                    MaintenanceActionTile(
                        title: "Cache",
                        description: "Clear temporary files and cached app data.",
                        detail: cacheSize,
                        icon: "internaldrive",
                        color: .orange,
                        buttonTitle: "Clear",
                        buttonIcon: "trash"
                    ) {
                        clearCache()
                    }

                    MaintenanceActionTile(
                        title: "Learnings Data",
                        description: "Delete recorded patterns and personalizations.",
                        detail: nil,
                        icon: "brain.head.profile",
                        color: .purple,
                        buttonTitle: "Delete All",
                        buttonIcon: "trash"
                    ) {
                        showingDeleteDataConfirmation = true
                    }

                    MaintenanceActionTile(
                        title: "Reset",
                        description: "Reset all preferences to defaults.",
                        detail: nil,
                        icon: "arrow.counterclockwise",
                        color: .red,
                        buttonTitle: "Reset All",
                        buttonIcon: "arrow.counterclockwise"
                    ) {
                        showingResetConfirmation = true
                    }
                }
            }
            .animatedAppearance(delay: 0.05)
            .onAppear {
                calculateCacheSize()
            }
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
            .alert("Reset All Settings?", isPresented: $showingResetConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button("Reset", role: .destructive) {
                    resetAllSettings()
                }
            } message: {
                Text("This will completely reset Sorty to its initial state, clearing all settings, history, and learnings. You'll go through onboarding again. This cannot be undone.")
            }
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
        HapticFeedbackManager.shared.success()
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

private struct MaintenanceActionTile: View {
    let title: String
    let description: String
    let detail: String?
    let icon: String
    let color: Color
    let buttonTitle: String
    let buttonIcon: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            action()
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(isHovered ? color : .secondary)
                    .frame(height: 24)
                    .accessibilityHidden(true)

                HStack(spacing: 6) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(isHovered ? .primary : .secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)

                    if let detail {
                        Text(detail)
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }

                Text(description)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(height: 32, alignment: .center)

                Label(buttonTitle, systemImage: buttonIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? color : .secondary)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, minHeight: 108)
            .padding(.horizontal, 10)
            .padding(.vertical, 12)
            .background(isHovered ? color.opacity(0.14) : Color.secondary.opacity(0.045))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isHovered ? color.opacity(0.32) : Color.secondary.opacity(0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
            if hovering {
                HapticFeedbackManager.shared.selection()
            }
        }
    }
}

#Preview {
    TroubleshootingSettingsView()
        .environmentObject(SettingsViewModel())
        .environmentObject(NotificationSettingsManager.shared)
        .environmentObject(AppState())
        .environmentObject(LearningsManager())
        .frame(width: 560, height: 300)
}
