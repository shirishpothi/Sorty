//
//  FinderIntegrationSettingsView.swift
//  Sorty
//
//  Finder Integration settings section
//

import SwiftUI

struct FinderIntegrationSettingsView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isOrganizeActionInstalled = false
    @State private var isWatchActionInstalled = false
    @State private var isExcludeActionInstalled = false
    @State private var watchActionMessage: String?
    @State private var finderSyncActive = false
    @State private var finderSyncMessage: String?
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
                            label: "Organize with Sorty",
                            isHealthy: isOrganizeActionInstalled
                        )

                        compactStatusRow(
                            label: "Watch with Sorty",
                            isHealthy: isWatchActionInstalled
                        )

                        compactStatusRow(
                            label: "Exclude with Sorty",
                            isHealthy: isExcludeActionInstalled
                        )

                        compactStatusRow(
                            label: "Finder extension",
                            isHealthy: finderSyncActive
                        )

                        compactStatusRow(
                            label: "Automation permission",
                            isHealthy: automationManager.automationStatus.isGranted
                        )
                    }
                }
            }
            .animatedAppearance(delay: 0.03)

            if shouldShowTroubleshooting {
                SettingsCard(title: "Troubleshooting", icon: "wrench.and.screwdriver", color: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sorty repairs the Finder menu action automatically where macOS allows it. Use these only if Finder still does not show Sorty actions.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        HStack(spacing: 8) {
                            Button(finderSyncActive ? "Repair Extension" : "Activate Extension") {
                                HapticFeedbackManager.shared.tap()
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
                                HapticFeedbackManager.shared.tap()
                                ExtensionCommunication.openFinderExtensionSettings()
                            }
                            .buttonStyle(.sortySecondary(size: .regular))

                            if !areFinderMenuActionsInstalled {
                                Button("Repair Menu Actions") {
                                    HapticFeedbackManager.shared.tap()
                                    Task {
                                        let result = await ExtensionCommunication.ensureQuickActionInstalledAsync(forceRefreshServices: true)
                                        await refreshIntegrationStatus()
                                        watchActionMessage = result.message
                                        if result.installed {
                                            HapticFeedbackManager.shared.success()
                                        } else {
                                            HapticFeedbackManager.shared.error()
                                        }
                                    }
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                            }

                            Button("Run Full Check") {
                                HapticFeedbackManager.shared.tap()
                                Task {
                                    await refreshIntegrationStatus()
                                    refreshFinderContext()
                                }
                            }
                            .buttonStyle(.sortySecondary(size: .regular))
                        }

                        if automationManager.automationStatus != .granted {
                            HStack(spacing: 8) {
                                Button("Open Automation Settings") {
                                    HapticFeedbackManager.shared.tap()
                                    automationManager.openAutomationSettings()
                                }
                                .buttonStyle(.sortySecondary(size: .regular))

                                Button("Recover Permission") {
                                    HapticFeedbackManager.shared.tap()
                                    automationManager.recoverAutomationState()
                                    refreshFinderContext()
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                                .accessibilityIdentifier("FinderAutomationRecoverButton")

                                Button {
                                    HapticFeedbackManager.shared.tap()
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
                    }
                }
                .animatedAppearance(delay: 0.1)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: shouldShowTroubleshooting)
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
    private func compactStatusRow(label: String, isHealthy: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? .green : .orange)
                .font(.caption)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHealthy ? "ready" : "needs attention")
    }

    private func refreshFinderContext() {
        automationManager.checkPermissions(enableChecksIfNeeded: true)
    }

    private var shouldShowTroubleshooting: Bool {
        !areFinderMenuActionsInstalled || !finderSyncActive || !automationManager.automationStatus.isGranted || finderSyncMessage != nil || watchActionMessage != nil
    }

    private var isFullyReady: Bool {
        areFinderMenuActionsInstalled && finderSyncActive && automationManager.automationStatus.isGranted
    }

    private var areFinderMenuActionsInstalled: Bool {
        isOrganizeActionInstalled && isWatchActionInstalled && isExcludeActionInstalled
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
            return "Use Finder's right-click menu to organize folders, add watched folders, or exclude paths. Sorty will keep checking this setup in the background."
        }

        if automationManager.automationStatus == .denied {
            return "macOS Automation permission is blocking Finder selection. Sorty can repair the rest automatically, but this permission must be re-enabled in System Settings."
        }

        return "Sorty installs and repairs the Finder menu actions automatically. If macOS needs confirmation, the repair options below will take you to the right place."
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

    private func refreshIntegrationStatus() async {
        _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
        let status = await ExtensionCommunication.getIntegrationStatusAsync()
        isOrganizeActionInstalled = status.quickActionInstalled
        isWatchActionInstalled = status.quickWatchActionInstalled
        isExcludeActionInstalled = status.quickExcludeActionInstalled
        finderSyncActive = status.finderSyncEnabled
    }
}

#Preview {
    FinderIntegrationSettingsView()
        .frame(width: 500, height: 400)
}
