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
    @State private var isShowingAutomationPermissionInfo = false
    @State private var isShowingMissingAutomationRecovery = false
    @State private var automationSettingsButtonFrameInScreen: CGRect = .zero
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
                            .symbolReplaceTransition(animationValue: overallStatusIcon)
                            .accessibilityHidden(true)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(overallStatusTitle)
                                .font(.subheadline.weight(.semibold))
                                .numericTextTransition(animationValue: overallStatusTitle)
                            Text(overallStatusSubtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                                .numericTextTransition(animationValue: overallStatusSubtitle)
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
                        .settingsFocusable(
                            .finderCheckStatus,
                            shape: Capsule(style: .continuous),
                            horizontalRingPadding: 4,
                            verticalRingPadding: 4
                        )
                    }

                    Divider()
                        .opacity(0.35)

                    VStack(spacing: 8) {
                        compactStatusRow(
                            label: "Organize with Sorty",
                            isHealthy: isOrganizeActionInstalled,
                            focusTarget: .finderOrganize
                        )

                        compactStatusRow(
                            label: "Watch with Sorty",
                            isHealthy: isWatchActionInstalled,
                            focusTarget: .finderWatch
                        )

                        compactStatusRow(
                            label: "Exclude from Sorty",
                            isHealthy: isExcludeActionInstalled,
                            focusTarget: .finderExclude
                        )

                        compactStatusRow(
                            label: "Automation permission",
                            isHealthy: automationManager.automationStatus.isGranted,
                            focusTarget: .finderAutomationPermission
                        )
                    }
                }
            }
            .settingsFocusable(.finderIntegration)
            .animatedAppearance(delay: 0.03)

            if shouldShowTroubleshooting {
                SettingsCard(title: "Troubleshooting", icon: "wrench.and.screwdriver", color: .purple) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Sorty uses macOS Quick Actions for Finder commands. Repair the menu actions if Finder does not show them.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 8) {
                                if !areFinderMenuActionsInstalled {
                                    repairMenuActionsButton()
                                }

                                runFullCheckButton()
                            }

                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    runFullCheckButton(expands: true)
                                }

                                if !areFinderMenuActionsInstalled {
                                    repairMenuActionsButton(expands: true)
                                }
                            }
                        }

                        if automationManager.automationStatus != .granted {
                            HStack(spacing: 8) {
                                Button("Open Automation Settings") {
                                    HapticFeedbackManager.shared.tap()
                                    automationManager.openAutomationSettings(
                                        sourceFrameInScreen: automationSettingsButtonFrameInScreen.isEmpty
                                            ? nil
                                            : automationSettingsButtonFrameInScreen.integral,
                                        onMissingApp: {
                                            isShowingMissingAutomationRecovery = true
                                        }
                                    )
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                                .background(
                                    ScreenFrameReader(frameInScreen: $automationSettingsButtonFrameInScreen)
                                        .allowsHitTesting(false)
                                )

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

                        if let message = watchActionMessage {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "info.circle")
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                    .accessibilityHidden(true)
                                Text(message)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .numericTextTransition(animationValue: message)
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
        .sheet(isPresented: $isShowingMissingAutomationRecovery) {
            AutomationPermissionRecoveryView {
                isShowingMissingAutomationRecovery = false
            }
        }
    }

    @ViewBuilder
    private func compactStatusRow(
        label: String,
        isHealthy: Bool,
        focusTarget: SettingsFocusTarget
    ) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isHealthy ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(isHealthy ? .green : .orange)
                .font(.caption)
                .symbolReplaceTransition(animationValue: isHealthy)
                .accessibilityHidden(true)
            Text(label)
                .font(.caption.weight(.medium))
            Spacer()
        }
        .settingsFocusableSetting(focusTarget)
        .accessibilityElement(children: .combine)
        .accessibilityValue(isHealthy ? "ready" : "needs attention")
    }

    private func refreshFinderContext() {
        automationManager.checkPermissions(enableChecksIfNeeded: true)
    }

    private func repairMenuActionsButton(expands: Bool = false) -> some View {
        Button {
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
        } label: {
            Text("Repair Menu Actions")
                .fixedSize(horizontal: !expands, vertical: false)
                .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.sortySecondary(size: .regular))
    }

    private func runFullCheckButton(expands: Bool = false) -> some View {
        Button {
            HapticFeedbackManager.shared.tap()
            Task {
                await refreshIntegrationStatus()
                refreshFinderContext()
            }
        } label: {
            Text("Run Full Check")
                .fixedSize(horizontal: !expands, vertical: false)
                .frame(maxWidth: expands ? .infinity : nil)
        }
        .buttonStyle(.sortySecondary(size: .regular))
    }

    private var shouldShowTroubleshooting: Bool {
        !areFinderMenuActionsInstalled || !automationManager.automationStatus.isGranted || watchActionMessage != nil
    }

    private var isFullyReady: Bool {
        areFinderMenuActionsInstalled && automationManager.automationStatus.isGranted
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
            return "Use Finder's right-click menu to organize folders, add watched folders, or exclude paths."
        }

        if automationManager.automationStatus == .denied {
            return "macOS Automation permission is blocking Finder selection. Sorty can repair the rest automatically, but this permission must be re-enabled in System Settings."
        }

        return "Sorty installs and repairs its macOS Quick Actions automatically."
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
    }
}

#Preview {
    FinderIntegrationSettingsView()
        .frame(width: 500, height: 400)
}
