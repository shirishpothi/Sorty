//
//  NotificationsSettingsView.swift
//  Sorty
//
//  Notifications settings section
//

import SwiftUI
import AppKit

struct NotificationsSettingsView: View {
    @EnvironmentObject var notificationSettings: NotificationSettingsManager
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var showAdvancedControlsOptIn = false

    private var showsAdvancedControls: Bool {
        FeatureFlags.advancedNotificationSettingsEnabled || showAdvancedControlsOptIn
    }

    private var hasFeatureFlagEnabled: Bool {
        FeatureFlags.advancedNotificationSettingsEnabled
    }
    
    var body: some View {
        VStack(spacing: 16) {
            // Permission Status
            NotificationPermissionCard()
                .animatedAppearance(delay: 0.0)

            if !hasFeatureFlagEnabled {
                advancedDiscoveryCard
                    .animatedAppearance(delay: 0.02)
            }
            
            if showsAdvancedControls {
                // NotifiCLI Status Card
                NotifiCLIStatusCard()
                    .animatedAppearance(delay: 0.05)
            }
            
            // Delivery Method
            SettingsCard(title: "Delivery Method", icon: "bell.badge", color: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.inAppHUD,
                        title: "In-App HUD",
                        description: "Show notifications as subtle bottom-left overlays",
                        previewAction: { notificationManager.previewInAppHUDDelivery() },
                        previewIcon: "play.fill"
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.systemNotifications,
                        title: "System Notifications",
                        description: "Show in macOS Notification Center",
                        previewAction: { notificationManager.previewSystemNotificationDelivery() },
                        previewIcon: "play.fill"
                    )
                    
                    if notificationSettings.settings.systemNotifications && showsAdvancedControls {
                        Divider()
                        
                        // Backend Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notification Backend")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Picker("Backend", selection: $notificationSettings.settings.notificationBackend) {
                                ForEach(NotificationBackend.allCases, id: \.self) { backend in
                                    Text(backend.displayName).tag(backend)
                                }
                            }
                            .pickerStyle(.segmented)
                            
                            Text(notificationSettings.settings.notificationBackend.description)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.1)
            
            // NotifiCLI Settings (advanced controls only)
            if showsAdvancedControls && notificationSettings.settings.notificationBackend == .notifiCLI {
                SettingsCard(title: "NotifiCLI Settings", icon: "bell.badge.waveform", color: .cyan) {
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsToggle(
                            isOn: $notificationSettings.settings.persistentNotifications,
                            title: "Persistent Notifications",
                            description: "Notifications stay on screen until dismissed"
                        )
                        
                        Divider()
                        
                        SettingsToggle(
                            isOn: $notificationSettings.settings.showActionButtons,
                            title: "Action Buttons",
                            description: "Show Undo, Open Folder, and other action buttons"
                        )
                        
                        Divider()
                        
                        // Sound Selection
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Notification Sound")
                                .font(.subheadline)
                                .fontWeight(.medium)
                            
                            Picker("Sound", selection: $notificationSettings.settings.notifiCLISound) {
                                Text("None").tag("")
                                ForEach(NotifiCLISound.allCases, id: \.rawValue) { sound in
                                    Text(sound.rawValue).tag(sound.rawValue)
                                }
                            }
                            .pickerStyle(.menu)
                            
                            Text("Sound played when notification appears")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .animatedAppearance(delay: 0.12)
            }
            
            // Notification Types
            SettingsCard(title: "Notification Types", icon: "list.bullet", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingComplete,
                        title: "Processing Complete",
                        description: "When file processing finishes successfully",
                        previewAction: { playPreviewSound("Glass") }
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.previewReady,
                        title: "Preview Ready",
                        description: "When AI has finished generating the organization plan",
                        previewAction: { playPreviewSound("Ping") }
                    )
                    
                    if showsAdvancedControls && notificationSettings.settings.previewReady {
                        SettingsToggle(
                            isOn: $notificationSettings.settings.showPreviewReadyInForeground,
                            title: "Show Preview Ready in foreground",
                            description: "Show system notification even when the app is active"
                        )
                        .padding(.leading, 12)
                    }
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingErrors,
                        title: "Processing Errors",
                        description: "When errors occur during processing",
                        previewAction: { playPreviewSound("Basso") }
                    )

                    if showsAdvancedControls {
                        Divider()
                        
                        SettingsToggle(
                            isOn: $notificationSettings.settings.batchSummary,
                            title: "Batch Summary",
                            description: "Summary notification after processing multiple files"
                        )
                        
                        Divider()
                        
                        SettingsToggle(
                            isOn: $notificationSettings.settings.alwaysShowCriticalErrors,
                            title: "Always Show Critical Errors",
                            description: "Display critical errors even if notifications are off"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.15)
            
            // Sounds
            SettingsCard(title: "Sounds", icon: "speaker.wave.2", color: .purple) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.playCompletionSound,
                        title: "Completion Sound",
                        description: "Play a satisfying sound when organization finishes",
                        previewAction: { playPreviewSound("Glass") }
                    )

                    if showsAdvancedControls {
                        Divider()
                        
                        SettingsToggle(
                            isOn: $notificationSettings.settings.systemNotificationSounds,
                            title: "System Notification Sounds",
                            description: "Play sound with system notifications"
                        )
                        
                        Divider()
                        
                        SettingsToggle(
                            isOn: $notificationSettings.settings.hudSounds,
                            title: "HUD Sounds",
                            description: "Play sound with in-app HUD notifications"
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.2)
            
            if showsAdvancedControls {
                // Test Notifications
                SettingsCard(title: "Test Notifications", icon: "bell.and.waves.left.and.right", color: .green) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Send test notifications to verify your settings are working correctly.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Test buttons row 1 - Basic notification types
                        HStack(spacing: 10) {
                            Button {
                                NotificationManager.shared.showInfo(
                                    title: "Test Info",
                                    message: "Your notifications are working correctly!"
                                )
                                HapticFeedbackManager.shared.success()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                    Text("Info")
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .accessibilityIdentifier("testInfoButton")
                            
                            Button {
                                NotificationManager.shared.showProcessingComplete(
                                    fileCount: 42,
                                    folderName: "Test Folder",
                                    folderPath: NSHomeDirectory() + "/Documents",
                                    canUndo: true
                                )
                                HapticFeedbackManager.shared.success()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "checkmark.circle")
                                    Text("Success")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("testSuccessButton")
                            
                            Button {
                                NotificationManager.shared.show(.previewReady(folderName: "Test Folder"))
                                HapticFeedbackManager.shared.success()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "eye")
                                    Text("Preview")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("testPreviewButton")
                            
                            Button {
                                NotificationManager.shared.showError(
                                    message: "This is a test error notification",
                                    isCritical: false,
                                    canRetry: true
                                )
                                HapticFeedbackManager.shared.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.triangle")
                                    Text("Error")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("testErrorButton")
                        }
                        
                        // Test buttons row 2 - Advanced notification types
                        HStack(spacing: 10) {
                            Button {
                                NotificationManager.shared.showBatchSummary(
                                    stats: BatchSummaryStats(
                                        filesMoved: 25,
                                        foldersCreated: 5,
                                        filesRenamed: 3,
                                        filesTagged: 8,
                                        duplicatesFound: 2,
                                        errorsEncountered: 0,
                                        duration: 4.5,
                                        folderName: "Documents",
                                        folderPath: NSHomeDirectory() + "/Documents",
                                        canUndo: true
                                    )
                                )
                                HapticFeedbackManager.shared.success()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "chart.bar")
                                    Text("Summary")
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .accessibilityIdentifier("testSummaryButton")
                            
                            Button {
                                NotificationManager.shared.showError(
                                    message: "Critical: Unable to access folder permissions",
                                    isCritical: true,
                                    canRetry: false
                                )
                                HapticFeedbackManager.shared.tap()
                            } label: {
                                HStack(spacing: 4) {
                                    Image(systemName: "exclamationmark.octagon")
                                    Text("Critical")
                                }
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                            .controlSize(.small)
                            .accessibilityIdentifier("testCriticalButton")
                        }
                        
                        // NotifiCLI action test
                        if notificationSettings.settings.notificationBackend == .notifiCLI {
                            Divider()
                            
                            VStack(alignment: .leading, spacing: 8) {
                                Text("NotifiCLI Enhanced Tests")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 10) {
                                    Button {
                                        Task {
                                            let response = await NotifiCLIService.shared.sendWithActions(
                                                title: "Test Action Buttons",
                                                message: "Click a button to test actionable notifications",
                                                actions: ["Undo", "Open Folder", "Dismiss"],
                                                sound: .glass,
                                                persistent: true
                                            )
                                            await MainActor.run {
                                                switch response {
                                                case .action(let label):
                                                    NotificationManager.shared.showInfo(
                                                        title: "Action Received",
                                                        message: "You clicked: \(label)"
                                                    )
                                                case .dismissed:
                                                    NotificationManager.shared.showInfo(
                                                        title: "Dismissed",
                                                        message: "Notification was dismissed"
                                                    )
                                                case .timeout:
                                                    NotificationManager.shared.showInfo(
                                                        title: "Timeout",
                                                        message: "Notification timed out"
                                                    )
                                                default:
                                                    break
                                                }
                                            }
                                        }
                                        HapticFeedbackManager.shared.success()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "hand.tap")
                                            Text("Actions")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("testActionsButton")
                                    
                                    Button {
                                        Task {
                                            await NotifiCLIService.shared.sendWithURL(
                                                title: "Open Link Test",
                                                message: "Click to open Sorty documentation",
                                                url: "https://github.com/shirishpothi/FileOrganizer",
                                                sound: .ping
                                            )
                                        }
                                        HapticFeedbackManager.shared.success()
                                    } label: {
                                        HStack(spacing: 4) {
                                            Image(systemName: "link")
                                            Text("URL")
                                        }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .accessibilityIdentifier("testURLButton")
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .animatedAppearance(delay: 0.25)

                notificationAnalyticsCard
                    .animatedAppearance(delay: 0.28)
            }
        }
    }

    private var advancedDiscoveryCard: some View {
        SettingsCard(title: "Advanced Controls", icon: "switch.2", color: .orange) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Want backend selection, actionable experiments, and diagnostics? You can opt in here without using Terminal flags.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show advanced notification controls in this session", isOn: $showAdvancedControlsOptIn)
                    .toggleStyle(.switch)
                    .font(.caption)
                    .accessibilityIdentifier("NotificationAdvancedOptInToggle")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func playPreviewSound(_ name: String) {
        if let sound = NSSound(named: NSSound.Name(name)) {
            sound.play()
        } else {
            NSSound.beep()
        }
        HapticFeedbackManager.shared.tap()
    }

    private var notificationAnalyticsCard: some View {
        SettingsCard(title: "Notification Analytics", icon: "chart.xyaxis.line", color: .indigo) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recent events: \\(notificationManager.analyticsEvents.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        notificationManager.clearAnalytics()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("NotificationAnalyticsClearButton")
                }

                if notificationManager.analyticsEvents.isEmpty {
                    Text("No analytics yet. Send a test notification to populate this list.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(notificationManager.analyticsEvents.prefix(6)) { event in
                        HStack(spacing: 8) {
                            Text(event.eventType.rawValue.capitalized)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.secondary.opacity(0.15))
                                .clipShape(Capsule())
                            Text(event.notificationType)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(event.backend.displayName)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

#Preview {
    NotificationsSettingsView()
        .frame(width: 500, height: 800)
}
