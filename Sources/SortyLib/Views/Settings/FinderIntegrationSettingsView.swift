//
//  FinderIntegrationSettingsView.swift
//  Sorty
//
//  Finder Integration settings section
//

import AppKit
import SwiftUI

struct FinderIntegrationSettingsView: View {
    @State private var isWatchActionInstalled = false
    @State private var watchActionMessage: String?
    @State private var finderSyncActive = false
    @State private var finderSyncMessage: String?
    @State private var frontmostFinderFolder: URL?
    @State private var isShowingAutomationPermissionInfo = false
    @EnvironmentObject var automationManager: AutomationManager
    
    var body: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Finder Integration", icon: "folder.badge.gearshape", color: .cyan) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: overallStatusIcon)
                            .font(.title3)
                            .foregroundStyle(overallStatusColor)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(overallStatusTitle)
                                .font(.subheadline.weight(.semibold))
                            Text(overallStatusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Check Now") {
                            Task {
                                await refreshIntegrationStatus()
                                refreshFinderContext()
                            }
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                        .accessibilityIdentifier("FinderIntegrationRefreshButton")
                    }

                    Divider()
                        .opacity(0.35)

                    VStack(spacing: 8) {
                        compactStatusRow(
                            label: "Finder menu actions",
                            value: isWatchActionInstalled ? "Ready" : "Repair available",
                            isHealthy: isWatchActionInstalled
                        )

                        compactStatusRow(
                            label: "Finder extension",
                            value: finderSyncActive ? "Active" : "Needs activation",
                            isHealthy: finderSyncActive
                        )

                        compactStatusRow(
                            label: "Automation permission",
                            value: automationStatusSummary,
                            isHealthy: automationManager.automationStatus.isGranted
                        )
                    }
                }
            }
            .animatedAppearance(delay: 0.03)

            SettingsCard(title: "Use Finder Now", icon: "sparkles.rectangle.stack", color: .mint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: automationManager.hasValidFinderSelection ? "checkmark.seal.fill" : "scope")
                            .font(.title3)
                            .foregroundStyle(automationManager.hasValidFinderSelection ? .green : .secondary)
                            .frame(width: 24, height: 24)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(finderContextTitle)
                                .font(.subheadline.weight(.medium))
                            Text(finderContextSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button("Refresh") {
                            refreshFinderContext()
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                        .accessibilityIdentifier("FinderWorkflowRefreshButton")
                    }

                    if let folder = frontmostFinderFolder {
                        HStack(spacing: 8) {
                            Image(systemName: "folder")
                                .foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Front Finder Folder")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                Text(folder.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }

                    HStack(spacing: 8) {
                        Button {
                            openFinderSelectionInSorty()
                        } label: {
                            Label("Organize Finder Selection", systemImage: "play.fill")
                        }
                        .buttonStyle(.sortyPrimary(size: .regular))
                        .disabled(!automationManager.hasValidFinderSelection && frontmostFinderFolder == nil)
                        .accessibilityIdentifier("FinderWorkflowOrganizeButton")

                        Button {
                            if let folder = frontmostFinderFolder {
                                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: folder.path)
                            }
                        } label: {
                            Label("Reveal Folder", systemImage: "folder")
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                        .disabled(frontmostFinderFolder == nil)
                        .accessibilityIdentifier("FinderWorkflowRevealButton")
                    }
                }
            }
            .animatedAppearance(delay: 0.06)

            if shouldShowTroubleshooting {
                SettingsCard(title: "Troubleshooting", icon: "wrench.and.screwdriver", color: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sorty repairs the Finder menu action automatically where macOS allows it. Use these only if Finder still does not show Sorty actions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Button(finderSyncActive ? "Repair Extension" : "Activate Extension") {
                                Task {
                                    let repair = await ExtensionCommunication.repairFinderSyncExtensionRegistrationAsync()
                                    finderSyncActive = await ExtensionCommunication.isFinderSyncExtensionActiveAsync()
                                    finderSyncMessage = repair.message
                                    if repair.success {
                                        HapticFeedbackManager.shared.success()
                                    } else {
                                        HapticFeedbackManager.shared.error()
                                    }
                                }
                            }
                            .buttonStyle(.sortyPrimary(size: .regular))

                            Button("Open macOS Extensions") {
                                ExtensionCommunication.openFinderExtensionSettings()
                            }
                            .buttonStyle(.sortySecondary(size: .regular))

                            if !isWatchActionInstalled {
                                Button("Repair Menu Action") {
                                    Task {
                                        let result = await ExtensionCommunication.installQuickWatchActionAsync()
                                        isWatchActionInstalled = result.success
                                        watchActionMessage = result.message
                                        if result.success {
                                            HapticFeedbackManager.shared.success()
                                        } else {
                                            HapticFeedbackManager.shared.error()
                                        }
                                    }
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                            }
                        }

                        if automationManager.automationStatus != .granted {
                            HStack(spacing: 8) {
                                Button("Open Automation Settings") {
                                    automationManager.openAutomationSettings()
                                }
                                .buttonStyle(.sortySecondary(size: .regular))

                                Button("Recover Permission") {
                                    automationManager.recoverAutomationState()
                                    refreshFinderContext()
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                                .accessibilityIdentifier("FinderAutomationRecoverButton")

                                Button {
                                    isShowingAutomationPermissionInfo = true
                                } label: {
                                    Label("Why this is needed", systemImage: "info.circle")
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if let message = finderSyncMessage ?? watchActionMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .transition(.scale.combined(with: .opacity))
                        }

                        Button("Run Full Check") {
                            Task {
                                await refreshIntegrationStatus()
                                refreshFinderContext()
                            }
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                    }
                }
                .animatedAppearance(delay: 0.1)
            }
        }
        .task {
            await refreshIntegrationStatus()
            refreshFinderContext()
        }
        .sheet(isPresented: $isShowingAutomationPermissionInfo) {
            PermissionEducationView(pages: [.automation]) {
                isShowingAutomationPermissionInfo = false
            }
        }
    }

    @ViewBuilder
    private func compactStatusRow(label: String, value: String, isHealthy: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? .green : .orange)
                .font(.caption)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(isHealthy ? .green : .orange)
        }
        .accessibilityElement(children: .combine)
    }

    private func refreshFinderContext() {
        automationManager.checkPermissions(enableChecksIfNeeded: true)
        if automationManager.automationStatus.isGranted {
            automationManager.updateFinderSelection()
            frontmostFinderFolder = automationManager.getFrontmostFinderWindow()
        } else {
            frontmostFinderFolder = nil
        }
    }

    private var shouldShowTroubleshooting: Bool {
        !isWatchActionInstalled || !finderSyncActive || !automationManager.automationStatus.isGranted || finderSyncMessage != nil || watchActionMessage != nil
    }

    private var isFullyReady: Bool {
        isWatchActionInstalled && finderSyncActive && automationManager.automationStatus.isGranted
    }

    private var overallStatusIcon: String {
        if isFullyReady {
            return "checkmark.circle.fill"
        }
        return automationManager.automationStatus == .denied ? "exclamationmark.triangle.fill" : "wrench.and.screwdriver.fill"
    }

    private var overallStatusColor: Color {
        if isFullyReady {
            return .green
        }
        return automationManager.automationStatus == .denied ? .orange : .cyan
    }

    private var overallStatusTitle: String {
        isFullyReady ? "Finder actions are ready" : "Sorty is finishing Finder setup"
    }

    private var overallStatusSubtitle: String {
        if isFullyReady {
            return "Use Finder's right-click menu to organize folders or add watched folders. Sorty will keep checking this setup in the background."
        }

        if automationManager.automationStatus == .denied {
            return "macOS Automation permission is blocking Finder selection. Sorty can repair the rest automatically, but this permission must be re-enabled in System Settings."
        }

        return "Sorty installs and repairs the Finder menu action automatically. If macOS needs confirmation, the repair options below will take you to the right place."
    }

    private var automationStatusSummary: String {
        switch automationManager.automationStatus {
        case .granted:
            return "Allowed"
        case .denied:
            return "Blocked"
        case .unknown:
            return "Checking"
        }
    }

    private var finderContextTitle: String {
        if automationManager.hasValidFinderSelection {
            return automationManager.statusMessage
        }

        if frontmostFinderFolder != nil {
            return "Ready to use the front Finder folder"
        }

        return "Open Finder or select items to organize"
    }

    private var finderContextSubtitle: String {
        if automationManager.selectedFinderItems.isEmpty {
            return "Sorty can organize the current Finder folder when macOS exposes it."
        }

        let itemCount = automationManager.selectedFinderItems.count
        return "Selection: \(itemCount) item\(itemCount == 1 ? "" : "s")"
    }

    private func openFinderSelectionInSorty() {
        let selectedTarget: URL? = automationManager.selectedFinderItems.first.map { item in
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            return isDirectory ? item : item.deletingLastPathComponent()
        }
        let target = selectedTarget ?? frontmostFinderFolder
        guard let target else { return }

        var components = URLComponents()
        components.scheme = "sorty"
        components.host = "organize"
        components.queryItems = [
            URLQueryItem(name: "path", value: target.path),
            URLQueryItem(name: "source", value: "finder")
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshIntegrationStatus() async {
        _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
        let status = await ExtensionCommunication.getIntegrationStatusAsync()
        isWatchActionInstalled = status.quickWatchActionInstalled
        finderSyncActive = status.finderSyncEnabled
    }
}

#Preview {
    FinderIntegrationSettingsView()
        .frame(width: 500, height: 400)
}
