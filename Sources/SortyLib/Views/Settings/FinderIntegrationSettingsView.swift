//
//  FinderIntegrationSettingsView.swift
//  Sorty
//
//  Finder Integration settings section
//

import SwiftUI

struct FinderIntegrationSettingsView: View {
    @State private var isWatchActionInstalled = false
    @State private var watchActionMessage: String?
    @State private var finderSyncActive = false
    @State private var finderSyncMessage: String?
    @State private var showAdvancedFinder = false
    @EnvironmentObject var automationManager: AutomationManager
    
    var body: some View {
        VStack(spacing: 16) {
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

            // URL Scheme Info
            SettingsCard(title: "URL Scheme", icon: "link", color: .blue) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trigger Sorty from scripts, Alfred, Raycast, or other apps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        URLSchemeRow(scheme: "sorty://organize?path=/path/to/folder", description: "Organize a folder")
                        URLSchemeRow(scheme: "sorty://duplicates?path=/path", description: "Find duplicates")
                        URLSchemeRow(scheme: "sorty://settings", description: "Open settings")
                        URLSchemeRow(scheme: "sorty://settings?section=provider", description: "Open AI Provider settings")
                        URLSchemeRow(scheme: "sorty://settings?section=notifications", description: "Open Notification settings")
                        URLSchemeRow(scheme: "sorty://watched", description: "Open watched folders")
                        URLSchemeRow(scheme: "sorty://exclusions", description: "Open exclusion rules")
                        URLSchemeRow(scheme: "sorty://storage", description: "Open storage locations")
                        URLSchemeRow(scheme: "sorty://learnings?action=honing", description: "Start a Learnings honing session")
                    }
                }
            }
            .animatedAppearance(delay: 0.15)
            
            // Advanced Controls
            SettingsCard(title: "Advanced Controls", icon: "slider.horizontal.3", color: .purple) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Global shortcuts, CLI tools, automation permissions, and more.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Button {
                        showAdvancedFinder = true
                    } label: {
                        HStack(spacing: 6) {
                            Text("Open Advanced Controls")
                                .font(.subheadline)
                            Image(systemName: "arrow.up.right.square")
                                .font(.caption)
                        }
                    }
                    .buttonStyle(.sortySecondary(size: .regular))
                    .accessibilityIdentifier("FinderAdvancedControlsButton")
                }
            }
            .animatedAppearance(delay: 0.2)
        }
        .sheet(isPresented: $showAdvancedFinder) {
            NavigationStack {
                FinderIntegrationView()
                    .environmentObject(automationManager)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") {
                                showAdvancedFinder = false
                            }
                        }
                    }
            }
            .frame(minWidth: 700, minHeight: 600)
        }
        .task {
            _ = await ExtensionCommunication.ensureQuickActionInstalledAsync()
            isWatchActionInstalled = await ExtensionCommunication.isQuickWatchActionInstalledAsync()
            finderSyncActive = await ExtensionCommunication.isFinderSyncExtensionActiveAsync()
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
}

#Preview {
    FinderIntegrationSettingsView()
        .frame(width: 500, height: 400)
}
