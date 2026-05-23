//
//  NotifiCLIStatusCard.swift
//  Sorty
//
//  NotifiCLI status card component
//

import SwiftUI

struct NotifiCLIStatusCard: View {
    @ObservedObject private var notificationManager = NotificationManager.shared
    @State private var isRebuilding = false
    @State private var installPath: String? = nil
    
    private var statusInfo: (icon: String, color: Color, title: String, description: String) {
        if notificationManager.isNotifiCLIAvailable {
            return ("checkmark.circle.fill", .green, "Ready", notificationManager.notifiCLISetupStatus)
        } else if notificationManager.notifiCLISetupStatus.contains("Setting up") {
            return ("arrow.triangle.2.circlepath", .blue, "Setting Up", notificationManager.notifiCLISetupStatus)
        } else {
            return ("exclamationmark.circle.fill", .orange, "Setup Required", "Tap Rebuild to setup enhanced notifications")
        }
    }
    
    var body: some View {
        SettingsCard(title: "Enhanced Notifications", icon: "bell.badge.waveform", color: .indigo) {
            VStack(alignment: .leading, spacing: 12) {
                // Status indicator
                HStack(spacing: 12) {
                    if notificationManager.notifiCLISetupStatus.contains("Setting up") {
                        SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                    } else {
                        Image(systemName: statusInfo.icon)
                            .font(.title2)
                            .foregroundStyle(statusInfo.color)
                    }
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(statusInfo.title)
                            .font(.subheadline.weight(.medium))
                        Text(statusInfo.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    
                    Spacer()
                    
                    Button {
                        rebuildNotifiCLI()
                    } label: {
                        if isRebuilding {
                            SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                        } else {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text(notificationManager.isNotifiCLIAvailable ? "Rebuild" : "Setup")
                            }
                        }
                    }
                    .buttonStyle(.sortyBordered)
                    .disabled(isRebuilding)
                }
                
                // Features list
                if notificationManager.isNotifiCLIAvailable {
                    Divider()
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Enhanced notification features:")
                            .font(.caption.weight(.medium))
                        
                        FeatureRow(icon: "hand.tap", text: "Actionable buttons: Undo, Open Folder, Retry")
                        FeatureRow(icon: "pin", text: "Persistent notifications that stay until dismissed")
                        FeatureRow(icon: "bell.badge.waveform", text: "Reliable notifications even when app is in background")
                        FeatureRow(icon: "speaker.wave.2", text: "Custom sounds: Glass, Ping, Pop, and more")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            loadInstallPath()
        }
    }
    
    private func rebuildNotifiCLI() {
        isRebuilding = true
        Task {
            _ = await NotifiCLIService.shared.rebuild()
            await notificationManager.checkNotifiCLIAvailability()
            await MainActor.run {
                isRebuilding = false
                HapticFeedbackManager.shared.success()
            }
        }
    }
    
    private func loadInstallPath() {
        Task {
            let info = await notificationManager.getNotifiCLIInfo()
            await MainActor.run {
                installPath = info.path
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 14)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NotifiCLIStatusCard()
        .frame(width: 400, height: 200)
}
