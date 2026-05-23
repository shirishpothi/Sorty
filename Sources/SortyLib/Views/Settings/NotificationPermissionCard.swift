//
//  NotificationPermissionCard.swift
//  Sorty
//
//  Notification permission status card component
//

import SwiftUI
import UserNotifications
import AppKit

struct NotificationPermissionCard: View {
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var isRequestingPermission = false
    
    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        switch notificationManager.notificationPermissionStatus {
        case .authorized:
            return ("checkmark.circle.fill", .green, "Authorized", "System notifications are enabled")
        case .denied:
            return ("xmark.circle.fill", .red, "Denied", "Open System Settings to enable notifications")
        case .provisional:
            return ("bell.badge.circle.fill", .orange, "Provisional", "Notifications delivered quietly")
        case .notDetermined:
            return ("questionmark.circle.fill", .secondary, "Not Set", "Request permission to enable system notifications")
        @unknown default:
            return ("questionmark.circle.fill", .secondary, "Unknown", "Unable to determine permission status")
        }
    }
    
    var body: some View {
        SettingsCard(title: "System Notification Permission", icon: "bell.badge.circle", color: .cyan) {
            VStack(alignment: .leading, spacing: 12) {
                // Status indicator
                HStack(spacing: 12) {
                    Image(systemName: statusInfo.icon)
                        .font(.title2)
                        .foregroundStyle(statusInfo.color)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusInfo.title)
                            .font(.subheadline.weight(.medium))
                        Text(statusInfo.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    Spacer()
                    
                    // Action button based on status
                    switch notificationManager.notificationPermissionStatus {
                    case .notDetermined:
                        Button {
                            requestPermission()
                        } label: {
                            HStack(spacing: 4) {
                                if isRequestingPermission {
                                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                                } else {
                                    Image(systemName: "bell.badge")
                                }
                                Text("Enable")
                            }
                        }
                        .buttonStyle(.sortyProminent)
                        .disabled(isRequestingPermission)
                        
                    case .denied:
                        Button {
                            openSystemSettings()
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "gear")
                                Text("Open Settings")
                            }
                        }
                        .buttonStyle(.sortyBordered)
                        
                    case .authorized, .provisional:
                        Button {
                            openSystemSettings()
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.sortyBordered)
                        .controlSize(.small)
                        .help("Open notification settings")
                        
                    default:
                        EmptyView()
                    }
                }
                
                // Note about HUD notifications
                if notificationManager.notificationPermissionStatus != .authorized {
                    HStack(spacing: 6) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.blue)
                        Text("In-app HUD notifications work regardless of this setting.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            Task {
                await notificationManager.checkNotificationPermission()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task {
                await notificationManager.checkNotificationPermission()
            }
        }
    }
    
    private func requestPermission() {
        HapticFeedbackManager.shared.tap()
        isRequestingPermission = true
        Task {
            let granted = await notificationManager.requestPermission()
            await notificationManager.checkNotificationPermission()

            await MainActor.run {
                isRequestingPermission = false
                let status = notificationManager.notificationPermissionStatus
                if granted || status == .authorized || status == .provisional {
                    HapticFeedbackManager.shared.success()
                } else {
                    HapticFeedbackManager.shared.error()
                    openSystemSettings()
                }
            }
        }
    }
    
    private func openSystemSettings() {
        // Open System Settings > Notifications
        let candidateURLs = [
            "x-apple.systempreferences:com.apple.preference.notifications",
            "x-apple.systempreferences:com.apple.Notifications-Settings.extension"
        ]

        for urlString in candidateURLs {
            if let url = URL(string: urlString), NSWorkspace.shared.open(url) {
                return
            }
        }

        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }
}

#Preview {
    NotificationPermissionCard()
        .frame(width: 400, height: 150)
}
