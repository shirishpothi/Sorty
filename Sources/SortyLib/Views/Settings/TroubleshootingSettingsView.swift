//
//  TroubleshootingSettingsView.swift
//  Sorty
//
//  Troubleshooting settings section
//

import SwiftUI

struct TroubleshootingSettingsView: View {
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var viewModel: SettingsViewModel
    @EnvironmentObject var learningsManager: LearningsManager
    @ObservedObject private var analytics = AnalyticsManager.shared
    
    @State private var cacheSize: String = "Calculating..."
    @State private var showingResetConfirmation = false
    @State private var showingDeleteDataConfirmation = false
    @State private var healthChecks: [SupportHealthCheck] = []
    @State private var isRunningHealthCheck = false
    
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
                        buttonIcon: "trash",
                        focusTarget: .troubleshootingCache
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
                        buttonIcon: "trash",
                        focusTarget: .troubleshootingLearnings
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
                        buttonIcon: "trash",
                        focusTarget: .troubleshootingReset
                    ) {
                        showingResetConfirmation = true
                    }
                }
            }
            .settingsFocusable(.troubleshootingMaintenance)
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

            SettingsCard(title: "Support Assistant", icon: "stethoscope", color: .teal) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(healthCheckSummary)
                                .font(.subheadline.weight(.semibold))

                            Text("Sorty checks its configuration and Finder integration locally, then points you to the exact setting that needs attention.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button {
                            runHealthCheck()
                        } label: {
                            Label(
                                isRunningHealthCheck ? "Checking" : healthChecks.isEmpty ? "Run Checks" : "Check Again",
                                systemImage: isRunningHealthCheck ? "arrow.trianglehead.2.clockwise.rotate.90" : "waveform.path.ecg"
                            )
                        }
                        .buttonStyle(.sortyBordered(intent: .info, size: .small))
                        .disabled(isRunningHealthCheck)
                        .accessibilityIdentifier("RunSupportHealthCheckButton")
                    }

                    if isRunningHealthCheck {
                        ProgressView()
                            .controlSize(.small)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if !healthChecks.isEmpty {
                        Divider()

                        VStack(spacing: 8) {
                            ForEach(healthChecks) { check in
                                SupportHealthCheckRow(check: check) {
                                    openSupportDestination(check.destination)
                                }
                            }
                        }
                    }
                }
            }
            .settingsFocusable(.troubleshootingAssistant)
            .animatedAppearance(delay: 0.12)
            .task {
                guard healthChecks.isEmpty else { return }
                runHealthCheck()
            }
        }
    }

    private var healthCheckSummary: String {
        if isRunningHealthCheck {
            return "Checking Sorty…"
        }
        guard !healthChecks.isEmpty else {
            return "Find and fix common problems"
        }
        let attentionCount = healthChecks.filter { $0.status == .needsAttention }.count
        return attentionCount == 0
            ? "Everything checked looks healthy"
            : "\(attentionCount) \(attentionCount == 1 ? "item needs" : "items need") attention"
    }

    private func runHealthCheck() {
        guard !isRunningHealthCheck else { return }
        isRunningHealthCheck = true
        AnalyticsManager.shared.captureFeature(
            feature: "support",
            subfeature: "health_check",
            action: "started",
            outcome: "started"
        )

        Task { @MainActor in
            let finderDiagnostics = await ExtensionCommunication.getFinderSyncDiagnosticsAsync()
            let config = viewModel.config
            var checks: [SupportHealthCheck] = []

            if config.requiresAPIKey,
               config.authMethod(for: config.provider) == .apiKey,
               config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                checks.append(
                    SupportHealthCheck(
                        id: "provider",
                        title: "AI Provider",
                        detail: "\(config.provider.displayName) needs an API key before Sorty can organize files.",
                        status: .needsAttention,
                        actionTitle: "Open Provider",
                        destination: .providerConfiguration
                    )
                )
            } else {
                checks.append(
                    SupportHealthCheck(
                        id: "provider",
                        title: "AI Provider",
                        detail: "\(config.provider.displayName) has the configuration required to make a request.",
                        status: .healthy,
                        actionTitle: nil,
                        destination: nil
                    )
                )
            }

            if FeatureFlags.internetPrivacyModeEnabled,
               config.provider != .ollama,
               config.provider != .appleFoundationModel {
                checks.append(
                    SupportHealthCheck(
                        id: "network",
                        title: "Internet Access",
                        detail: "Block Internet Connections is preventing \(config.provider.displayName) from receiving requests.",
                        status: .needsAttention,
                        actionTitle: "Review Setting",
                        destination: .advancedInternetPrivacy
                    )
                )
            } else {
                checks.append(
                    SupportHealthCheck(
                        id: "network",
                        title: "Internet Access",
                        detail: FeatureFlags.internetPrivacyModeEnabled
                            ? "Sorty is configured for an offline provider."
                            : "Sorty is allowed to contact the configured provider.",
                        status: .healthy,
                        actionTitle: nil,
                        destination: nil
                    )
                )
            }

            checks.append(
                SupportHealthCheck(
                    id: "finder",
                    title: "Finder Integration",
                    detail: finderDiagnostics.detailMessage,
                    status: finderDiagnostics.isOperational ? .healthy : .needsAttention,
                    actionTitle: finderDiagnostics.isOperational ? nil : "Open Repair",
                    destination: finderDiagnostics.isOperational ? nil : .finderExtension
                )
            )

            let analyticsDetail: String
            let analyticsStatus: SupportHealthStatus
            if analytics.isActive {
                analyticsDetail = "Anonymous reliability analytics are active and can help classify support problems."
                analyticsStatus = .healthy
            } else if analytics.consent == .granted {
                analyticsDetail = "Analytics are allowed but currently paused by an app privacy setting."
                analyticsStatus = .informational
            } else {
                analyticsDetail = "Analytics are off. Local checks and support reports still work normally."
                analyticsStatus = .informational
            }
            checks.append(
                SupportHealthCheck(
                    id: "analytics",
                    title: "Support Context",
                    detail: analyticsDetail,
                    status: analyticsStatus,
                    actionTitle: analytics.isActive ? nil : "Privacy Settings",
                    destination: analytics.isActive ? nil : .advancedAnalytics
                )
            )

            healthChecks = checks
            isRunningHealthCheck = false

            let attentionCount = checks.filter { $0.status == .needsAttention }.count
            AnalyticsManager.shared.captureFeature(
                feature: "support",
                subfeature: "health_check",
                action: "completed",
                outcome: attentionCount == 0 ? "healthy" : "attention_needed",
                properties: [
                    "count_bucket": AnalyticsManager.countBucket(attentionCount),
                ]
            )
        }
    }

    private func openSupportDestination(_ destination: SettingsFocusTarget?) {
        guard let destination else { return }
        AnalyticsManager.shared.captureFeature(
            feature: "support",
            subfeature: "health_check",
            action: "opened_recovery",
            outcome: "success",
            properties: ["selection_kind": destination.rawValue]
        )
        HapticFeedbackManager.shared.tap()
        appState.openSettingsWindow(focusTarget: destination)
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

private enum SupportHealthStatus: Equatable {
    case healthy
    case needsAttention
    case informational

    var icon: String {
        switch self {
        case .healthy: return "checkmark.circle.fill"
        case .needsAttention: return "exclamationmark.triangle.fill"
        case .informational: return "info.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .healthy: return .green
        case .needsAttention: return .orange
        case .informational: return .blue
        }
    }

    var reportLabel: String {
        switch self {
        case .healthy: return "Healthy"
        case .needsAttention: return "Needs attention"
        case .informational: return "Information"
        }
    }
}

private struct SupportHealthCheck: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: SupportHealthStatus
    let actionTitle: String?
    let destination: SettingsFocusTarget?
}

private struct SupportHealthCheckRow: View {
    let check: SupportHealthCheck
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: check.status.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(check.status.color)
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(check.title)
                    .font(.subheadline.weight(.semibold))

                Text(check.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(check.title), \(check.status.reportLabel)")
            .accessibilityHint(check.detail)

            Spacer(minLength: 8)

            if let actionTitle = check.actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(.sortyBordered(intent: .info, size: .small))
            }
        }
        .padding(10)
        .background(check.status.color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct MaintenanceActionTile: View {
    let title: String
    let description: String
    let detail: String?
    let icon: String
    let color: Color
    let buttonTitle: String
    let buttonIcon: String
    let focusTarget: SettingsFocusTarget
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
                            .numericTextTransition(animationValue: detail)
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
        .settingsFocusable(
            focusTarget,
            shape: RoundedRectangle(cornerRadius: 8, style: .continuous)
        )
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
