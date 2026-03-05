//
//  FinderIntegrationSettingsView.swift
//  Sorty
//
//  Finder Integration settings section
//

import SwiftUI
import AppKit

struct FinderIntegrationSettingsView: View {
    @State private var isWatchActionInstalled = false
    @State private var watchActionMessage: String?
    @State private var finderSyncActive = false
    @State private var finderSyncMessage: String?
    @State private var frontmostFinderFolder: URL?
    @EnvironmentObject var automationManager: AutomationManager
    
    var body: some View {
        VStack(spacing: 16) {
            // Integration Status
            SettingsCard(title: "Integration Status", icon: "checkmark.shield", color: .teal) {
                VStack(alignment: .leading, spacing: 10) {
                    statusRow(
                        label: "Watch Action",
                        value: isWatchActionInstalled ? "Installed" : "Not installed",
                        isHealthy: isWatchActionInstalled
                    )

                    statusRow(
                        label: "Finder Extension",
                        value: finderSyncActive ? "Active" : "Needs activation",
                        isHealthy: finderSyncActive
                    )

                    HStack {
                        Text("Use the sections below to install or repair each integration.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Refresh") {
                            Task {
                                await refreshIntegrationStatus()
                                refreshFinderContext()
                            }
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                        .accessibilityIdentifier("FinderIntegrationRefreshButton")
                    }
                }
            }
            .animatedAppearance(delay: 0.03)

            // Quick Actions
            SettingsCard(title: "Quick Actions", icon: "cursorarrow.click.badge.clock", color: .cyan) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.caption)
                        Text("'Organize with Sorty' now appears only in Finder's main right-click menu (via Finder Sync), not under Quick Actions.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    // Watch with Sorty
                    quickActionRow(
                        title: "Watch with Sorty",
                        description: "Right-click to add a folder to your watched folders",
                        isInstalled: isWatchActionInstalled,
                        message: watchActionMessage,
                        installAction: {
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
                        },
                        uninstallAction: {
                            Task {
                                if await ExtensionCommunication.uninstallQuickWatchActionAsync() {
                                    isWatchActionInstalled = false
                                    watchActionMessage = "Watch Action removed"
                                    HapticFeedbackManager.shared.success()
                                }
                            }
                        }
                    )
                }
            }
            .animatedAppearance(delay: 0.05)

            // Finder Extension
            SettingsCard(title: "Finder Extension", icon: "puzzlepiece.extension", color: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: finderSyncActive ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(finderSyncActive ? .green : .orange)
                        Text(finderSyncActive ? "Extension Active" : "Needs Repair or Activation")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(finderSyncActive ? .green : .orange)
                    }

                    HStack(spacing: 8) {
                        Button(finderSyncActive ? "Repair" : "Activate") {
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

                        Button("Open Extensions") {
                            ExtensionCommunication.openFinderExtensionSettings()
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                    }

                    if let message = finderSyncMessage {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "puzzlepiece.extension")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text(message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            .animatedAppearance(delay: 0.1)
            
            // Finder Workflow
            SettingsCard(title: "Finder Workflow", icon: "sparkles.rectangle.stack", color: .mint) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: automationManager.hasValidFinderSelection ? "checkmark.seal.fill" : "scope")
                            .font(.title3)
                            .foregroundStyle(automationManager.hasValidFinderSelection ? .green : .secondary)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(automationManager.statusMessage)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text("Selection: \(automationManager.selectedFinderItems.count) item\(automationManager.selectedFinderItems.count == 1 ? "" : "s")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
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
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Front Finder Folder")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                                PrivacySensitivePathText(path: folder.path)
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
            .animatedAppearance(delay: 0.15)

            // Automation Permission
            SettingsCard(title: "Automation Permission", icon: "gearshape.2", color: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: automationStatusIcon)
                            .font(.title3)
                            .foregroundStyle(automationStatusColor)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(automationStatusTitle)
                                .font(.subheadline.weight(.medium))
                            Text(automationStatusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if automationManager.automationStatus == .denied {
                            Button("Open System Settings") {
                                automationManager.openAutomationSettings()
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                        }
                    }

                    if automationManager.automationStatus == .denied {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                                .font(.caption)
                            Text("Without this permission, Finder selection and one-click Finder workflows will not work.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.orange.opacity(0.08))
                        .cornerRadius(8)
                    }

                    if automationManager.automationStatus == .unknown {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Text("Permission status is unknown. Click Recover to run a fresh permission check.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(8)
                        .background(Color.secondary.opacity(0.06))
                        .cornerRadius(8)
                    }

                    HStack(spacing: 8) {
                        Text(automationManager.statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Recover") {
                            automationManager.recoverAutomationState()
                            refreshFinderContext()
                        }
                        .buttonStyle(.sortySecondary(size: .regular))
                        .accessibilityIdentifier("FinderAutomationRecoverButton")
                    }
                }
            }
            .animatedAppearance(delay: 0.2)
        }
        .task {
            await refreshIntegrationStatus()
            refreshFinderContext()
        }
    }

    @ViewBuilder
    private func statusRow(label: String, value: String, isHealthy: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? .green : .orange)
                .font(.caption)
            Text(label)
                .font(.subheadline)
            Spacer()
            Text(value)
                .font(.caption.weight(.medium))
                .foregroundStyle(isHealthy ? .green : .orange)
        }
    }

    @ViewBuilder
    private func quickActionRow(
        title: String,
        description: String,
        isInstalled: Bool,
        message: String?,
        installAction: @escaping () -> Void,
        uninstallAction: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isInstalled ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.title3)
                    .foregroundStyle(isInstalled ? .green : .secondary)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if isInstalled {
                    Button("Uninstall") {
                        uninstallAction()
                    }
                    .buttonStyle(.sortySecondary(size: .regular))
                } else {
                    Button("Install") {
                        installAction()
                    }
                    .buttonStyle(.sortyPrimary(size: .regular))
                }
            }

            if let message = message {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: isInstalled ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(isInstalled ? .green : .orange)
                        .font(.caption)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
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

    private var automationStatusTitle: String {
        switch automationManager.automationStatus {
        case .granted:
            return "Automation Granted"
        case .denied:
            return "Automation Denied"
        case .unknown:
            return "Automation Status Unknown"
        }
    }

    private var automationStatusSubtitle: String {
        switch automationManager.automationStatus {
        case .granted:
            return "Finder integration can read selections and run Finder-driven actions."
        case .denied:
            return "Required to read Finder selection and run Finder-driven actions."
        case .unknown:
            return "Status has not been confirmed yet."
        }
    }

    private var automationStatusIcon: String {
        switch automationManager.automationStatus {
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.circle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }

    private var automationStatusColor: Color {
        switch automationManager.automationStatus {
        case .granted:
            return .green
        case .denied:
            return .red
        case .unknown:
            return .orange
        }
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
