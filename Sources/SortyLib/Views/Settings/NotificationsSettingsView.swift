//
//  NotificationsSettingsView.swift
//  Sorty
//
//  Notifications settings section
//

import AppKit
import SwiftUI

struct NotificationsSettingsView: View {
    @EnvironmentObject var notificationSettings: NotificationSettingsManager
    @ObservedObject private var notificationManager = NotificationManager.shared
    
    var body: some View {
        VStack(spacing: 16) {
            // Permission Status
            NotificationPermissionCard()
                .settingsFocusable(.notificationsPermission)
                .animatedAppearance(delay: 0.0)
            
            // Delivery Method
            SettingsCard(title: "Delivery Method", icon: "bell.badge", color: .pink) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.inAppHUD,
                        title: "In-App HUD",
                        description: "Show notifications as subtle bottom-left overlays",
                        previewAction: { notificationManager.previewInAppHUDDelivery() },
                        previewIcon: "play.fill",
                        focusTarget: .notificationsInAppHUD
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.systemNotifications,
                        title: "System Notifications",
                        description: "Show in macOS Notification Center",
                        previewAction: { notificationManager.previewSystemNotificationDelivery() },
                        previewIcon: "play.fill",
                        focusTarget: .notificationsSystem
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .animatedAppearance(delay: 0.1)
            
            // Notification Types
            SettingsCard(title: "Notification Types", icon: "list.bullet", color: .blue) {
                VStack(alignment: .leading, spacing: 12) {
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingComplete,
                        title: "Processing Complete",
                        description: "When file processing finishes successfully",
                        previewAction: { playPreviewSound("Glass") },
                        focusTarget: .notificationsProcessingComplete
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.previewReady,
                        title: "Preview Ready",
                        description: "When Sorty has finished generating the organization plan",
                        previewAction: { playPreviewSound("Ping") },
                        focusTarget: .notificationsPreviewReady
                    )
                    
                    Divider()
                    
                    SettingsToggle(
                        isOn: $notificationSettings.settings.processingErrors,
                        title: "Processing Errors",
                        description: "When errors occur during processing",
                        previewAction: { playPreviewSound("Basso") },
                        focusTarget: .notificationsProcessingErrors
                    )

                    Divider()

                    SettingsToggle(
                        isOn: watchedFolderActivityNotifications,
                        title: "Watched Folder Activity",
                        description: "When Sorty starts or finishes organizing detected additions",
                        previewAction: { notificationManager.previewWatchedFolderActivity() },
                        previewIcon: "play.fill",
                        focusTarget: .notificationsWatchedFolderFinished
                    )

                    Divider()

                    SettingsToggle(
                        isOn: $notificationSettings.settings.playCompletionSound,
                        title: "Completion Sound",
                        description: "Play a satisfying sound when organization finishes",
                        previewAction: { playPreviewSound("Glass") },
                        focusTarget: .notificationsCompletionSound
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .settingsFocusable(.notificationsTypes)
            .animatedAppearance(delay: 0.15)
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

    private var watchedFolderActivityNotifications: Binding<Bool> {
        Binding(
            get: {
                notificationSettings.settings.watchedFolderStartNotificationsEnabled &&
                    notificationSettings.settings.watchedFolderCompletionNotificationsEnabled
            },
            set: { isEnabled in
                notificationSettings.settings.watchedFolderStartNotificationsEnabled = isEnabled
                notificationSettings.settings.watchedFolderCompletionNotificationsEnabled = isEnabled
            }
        )
    }

}

#Preview {
    NotificationsSettingsView()
        .frame(width: 500, height: 800)
}
