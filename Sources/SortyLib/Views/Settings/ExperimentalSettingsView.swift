//
//  ExperimentalSettingsView.swift
//  Sorty
//
//  Experimental features section showing disabled feature flags with enablement guidance
//

import SwiftUI

struct ExperimentalSettingsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("These features are available but disabled by default. You can enable them directly here or with Terminal commands.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ForEach(experimentalFlags) { flag in
                ExperimentalFlagRow(flag: flag)
            }
        }
    }

    private var experimentalFlags: [ExperimentalFlag] {
        [
            ExperimentalFlag(
                name: "Sensitive Action Authentication",
                description: "Require Touch ID or your system password before revealing secrets, changing network privacy mode, or opening destructive confirmations.",
                defaultsKey: "sensitiveActionAuthenticationEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app sensitiveActionAuthenticationEnabled -bool true",
                disableCommand: "defaults write com.sorty.app sensitiveActionAuthenticationEnabled -bool false"
            ),
            ExperimentalFlag(
                name: "Finder Integration",
                description: "Show Sorty's Finder integration UI and repair flow. macOS still controls whether the Finder Sync extension is actually enabled.",
                defaultsKey: "finderIntegrationEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app finderIntegrationEnabled -bool true",
                disableCommand: "defaults write com.sorty.app finderIntegrationEnabled -bool false"
            ),
            ExperimentalFlag(
                name: "Batch Organization",
                description: "Organize multiple folders at once with concurrent processing and batch preview/apply.",
                defaultsKey: "batchOrganizationEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app batchOrganizationEnabled -bool true",
                disableCommand: "defaults write com.sorty.app batchOrganizationEnabled -bool false"
            ),
            ExperimentalFlag(
                name: "GitHub Update Checker",
                description: "In-app update dialog using GitHub Releases. Sparkle handles updates by default.",
                defaultsKey: "githubUpdateCheckerEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app githubUpdateCheckerEnabled -bool true",
                disableCommand: "defaults write com.sorty.app githubUpdateCheckerEnabled -bool false"
            ),
            ExperimentalFlag(
                name: "Advanced Notification Controls",
                description: "Shows technical notification controls including backend selection and test actions.",
                defaultsKey: "advancedNotificationSettingsEnabled",
                defaultValue: false,
                enableCommand: "defaults write com.sorty.app advancedNotificationSettingsEnabled -bool true",
                disableCommand: "defaults write com.sorty.app advancedNotificationSettingsEnabled -bool false"
            ),
        ]
    }
}

struct ExperimentalFlag: Identifiable {
    let id = UUID()
    let name: String
    let description: String
    let defaultsKey: String
    let defaultValue: Bool
    let enableCommand: String
    let disableCommand: String

    func currentValue() -> Bool {
        if UserDefaults.standard.object(forKey: defaultsKey) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: defaultsKey)
    }
}

struct ExperimentalFlagRow: View {
    let flag: ExperimentalFlag
    @State private var copied = false
    @State private var isEnabled: Bool
    @State private var setupMessage: String?
    @State private var finderSyncDiagnostics: ExtensionCommunication.FinderSyncDiagnostics?
    @State private var isRepairingFinderSync = false

    init(flag: ExperimentalFlag) {
        self.flag = flag
        _isEnabled = State(initialValue: flag.currentValue())
    }

    var body: some View {
        SettingsCard(title: flag.name, icon: isEnabled ? "checkmark.circle.fill" : "circle.dashed", color: isEnabled ? .green : .secondary) {
            VStack(alignment: .leading, spacing: 10) {
                Text(flag.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle(
                    "Enable in Sorty",
                    isOn: Binding(
                        get: { isEnabled },
                        set: { newValue in
                            guard isEnabled != newValue else { return }
                            Task {
                                let didAuthenticate = await SecurityManager.shared.authenticateForSensitiveAction(
                                    reason: "Authenticate to change the \(flag.name) experimental setting."
                                )
                                guard didAuthenticate else {
                                    HapticFeedbackManager.shared.error()
                                    return
                                }
                                await applyFlagValue(newValue)
                            }
                        }
                    )
                )
                .toggleStyle(.switch)

                HStack(spacing: 8) {
                    Circle()
                        .fill(isEnabled ? Color.green : Color.orange)
                        .frame(width: 8, height: 8)
                    Text(isEnabled ? "Feature Flag Enabled" : "Feature Flag Disabled")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(isEnabled ? .green : .orange)
                }

                if let availabilityStatus = finderIntegrationAvailabilityStatus {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: finderIntegrationAvailabilityIcon)
                                .foregroundStyle(finderIntegrationAvailabilityColor)
                                .font(.caption)
                            Text(availabilityStatus.title)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(finderIntegrationAvailabilityColor)
                        }

                        Text(availabilityStatus.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if availabilityStatus.state == .setupPending {
                            HStack(spacing: 8) {
                                Button(isRepairingFinderSync ? "Repairing..." : "Repair Finder Sync") {
                                    Task {
                                        isRepairingFinderSync = true
                                        let repair = await ExtensionCommunication.repairFinderSyncExtensionRegistrationAsync()
                                        setupMessage = repair.message
                                        await refreshFinderIntegrationRuntimeState()
                                        isRepairingFinderSync = false

                                        if repair.success {
                                            HapticFeedbackManager.shared.success()
                                        } else {
                                            HapticFeedbackManager.shared.error()
                                        }
                                    }
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                                .disabled(isRepairingFinderSync)

                                Button("Open Extensions") {
                                    ExtensionCommunication.openFinderExtensionSettings()
                                    HapticFeedbackManager.shared.selection()
                                }
                                .buttonStyle(.sortySecondary(size: .regular))
                            }
                        }
                    }
                    .padding(10)
                    .background(finderIntegrationAvailabilityBackground)
                    .cornerRadius(8)
                }

                if let setupMessage, flag.defaultsKey == "finderIntegrationEnabled" {
                    Text(setupMessage)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                let command = isEnabled ? flag.disableCommand : flag.enableCommand
                HStack(spacing: 8) {
                    Text(command)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .textSelection(.enabled)

                    Spacer()

                    Button {
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(command, forType: .string)
                        HapticFeedbackManager.shared.tap()
                        withAnimation { copied = true }
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 1_500_000_000)
                            withAnimation { copied = false }
                        }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                            .font(.caption2)
                            .foregroundStyle(copied ? .green : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Copy command")
                }
                .padding(8)
                .background(Color.black.opacity(0.05))
                .cornerRadius(6)

                Text("Relaunch Sorty to ensure all views pick up this change.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .onAppear {
            isEnabled = flag.currentValue()
        }
        .task(id: isEnabled) {
            await refreshFinderIntegrationRuntimeState()
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("ExperimentalFlag-\(flag.name)")
    }

    private var finderIntegrationAvailabilityStatus: ExtensionCommunication.FinderIntegrationAvailabilityStatus? {
        guard flag.defaultsKey == "finderIntegrationEnabled" else { return nil }
        return ExtensionCommunication.finderIntegrationAvailabilityStatus(
            featureFlagEnabled: isEnabled,
            diagnostics: finderSyncDiagnostics
        )
    }

    private var finderIntegrationAvailabilityColor: Color {
        guard let status = finderIntegrationAvailabilityStatus else { return .secondary }
        switch status.state {
        case .featureDisabled:
            return .secondary
        case .checking:
            return .orange
        case .setupPending:
            return .orange
        case .ready:
            return .green
        }
    }

    private var finderIntegrationAvailabilityIcon: String {
        guard let status = finderIntegrationAvailabilityStatus else { return "questionmark.circle.fill" }
        switch status.state {
        case .featureDisabled:
            return "circle.dashed"
        case .checking:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .setupPending:
            return "exclamationmark.triangle.fill"
        case .ready:
            return "checkmark.circle.fill"
        }
    }

    private var finderIntegrationAvailabilityBackground: Color {
        guard let status = finderIntegrationAvailabilityStatus else { return Color.secondary.opacity(0.06) }
        switch status.state {
        case .featureDisabled:
            return Color.secondary.opacity(0.06)
        case .checking:
            return Color.orange.opacity(0.08)
        case .setupPending:
            return Color.orange.opacity(0.08)
        case .ready:
            return Color.green.opacity(0.08)
        }
    }

    private func refreshFinderIntegrationRuntimeState() async {
        guard flag.defaultsKey == "finderIntegrationEnabled", isEnabled else {
            finderSyncDiagnostics = nil
            return
        }

        ExtensionCommunication.beginMonitoringFinderSyncRuntime()
        finderSyncDiagnostics = await ExtensionCommunication.getFinderSyncDiagnosticsAsync()
    }

    @MainActor
    private func applyFlagValue(_ newValue: Bool) async {
        UserDefaults.standard.set(newValue, forKey: flag.defaultsKey)

        if flag.defaultsKey == "finderIntegrationEnabled" {
            if newValue {
                let quickActionResult = ExtensionCommunication.ensureQuickActionInstalled()
                setupMessage = quickActionResult.message
                await refreshFinderIntegrationRuntimeState()
            } else {
                setupMessage = nil
                finderSyncDiagnostics = nil
            }
        }

        withAnimation(.easeOut(duration: 0.2)) {
            isEnabled = newValue
        }
        HapticFeedbackManager.shared.selection()
    }
}

#Preview {
    ExperimentalSettingsView()
        .frame(width: 500, height: 600)
}
