//
//  TroubleshootingSettingsView.swift
//  Sorty
//
//  Troubleshooting settings section
//

import SwiftUI

struct TroubleshootingSettingsView: View {
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
                        title: "All Sorty Data",
                        description: "Erase settings, history, learnings, credentials, and caches.",
                        detail: nil,
                        icon: "arrow.counterclockwise",
                        color: .red,
                        buttonTitle: "Erase All",
                        buttonIcon: "trash"
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
            .alert("Erase All Sorty Data?", isPresented: $showingResetConfirmation) {
                Button("Keep Data", role: .cancel) {}
                Button("Erase All Data", role: .destructive) {
                    appState.deleteUsageData()
                }
            } message: {
                Text("This permanently removes Sorty settings, history, learnings, saved credentials, and caches from this Mac. You'll return to onboarding. This cannot be undone.")
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
        let fileManager = FileManager.default

        return cacheDirectories.reduce(into: 0) { totalSize, cacheDirectory in
            if fileManager.fileExists(atPath: cacheDirectory.path) {
                totalSize += directorySize(at: cacheDirectory)
            }
        }
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
        var deletionErrors: [Error] = []

        for cacheDirectory in cacheDirectories where fileManager.fileExists(atPath: cacheDirectory.path) {
            do {
                try fileManager.removeItem(at: cacheDirectory)
            } catch {
                deletionErrors.append(error)
            }
        }

        FileThumbnailProvider.shared.clearCache()
        FolderThumbnailProvider.shared.clearCache()
        calculateCacheSize()

        if let error = deletionErrors.first {
            HapticFeedbackManager.shared.error()
            NotificationManager.shared.showError(
                message: "Some cached data could not be cleared: \(error.localizedDescription)"
            )
        } else {
            HapticFeedbackManager.shared.success()
        }
    }

    private var cacheDirectories: [URL] {
        let fileManager = FileManager.default
        let bundleId = Bundle.main.bundleIdentifier ?? "com.sorty.app"
        var directories: [URL] = []

        if let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first {
            directories.append(cachesURL.appendingPathComponent(bundleId, isDirectory: true))
            directories.append(cachesURL.appendingPathComponent("Sorty", isDirectory: true))
        }

        if let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first {
            let sortySupport = appSupportURL.appendingPathComponent("Sorty", isDirectory: true)
            directories.append(sortySupport.appendingPathComponent("Cache", isDirectory: true))
            directories.append(sortySupport.appendingPathComponent("ModelCache", isDirectory: true))
        }

        return directories
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
                    Text(LocalizedStringKey(title))
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

                Text(LocalizedStringKey(description))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(minHeight: 32, alignment: .center)

                Label(buttonTitle, systemImage: buttonIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isHovered ? color : .secondary)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, minHeight: 124)
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
