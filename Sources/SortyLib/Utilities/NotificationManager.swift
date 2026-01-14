//
//  NotificationManager.swift
//  Sorty
//
//  Unified notification manager for HUD and system notifications
//

import Foundation
import SwiftUI
import UserNotifications
import AppKit

/// Detailed statistics for batch organization summary
public struct BatchSummaryStats: Sendable {
    public let filesMoved: Int
    public let foldersCreated: Int
    public let filesRenamed: Int
    public let filesTagged: Int
    public let duplicatesFound: Int
    public let errorsEncountered: Int
    public let duration: TimeInterval
    public let folderName: String
    
    public init(
        filesMoved: Int = 0,
        foldersCreated: Int = 0,
        filesRenamed: Int = 0,
        filesTagged: Int = 0,
        duplicatesFound: Int = 0,
        errorsEncountered: Int = 0,
        duration: TimeInterval = 0,
        folderName: String = ""
    ) {
        self.filesMoved = filesMoved
        self.foldersCreated = foldersCreated
        self.filesRenamed = filesRenamed
        self.filesTagged = filesTagged
        self.duplicatesFound = duplicatesFound
        self.errorsEncountered = errorsEncountered
        self.duration = duration
        self.folderName = folderName
    }
    
    /// Total number of operations performed
    public var totalOperations: Int {
        filesMoved + filesRenamed + filesTagged
    }
    
    /// Whether the batch had any errors
    public var hasErrors: Bool {
        errorsEncountered > 0
    }
    
    /// Whether the batch was successful (at least some operations completed)
    public var isSuccessful: Bool {
        totalOperations > 0 || foldersCreated > 0
    }
}

/// Types of notifications the app can show
public enum NotificationType: Sendable {
    case processingComplete(fileCount: Int, folderName: String)
    case processingError(message: String, isCritical: Bool)
    case batchSummary(stats: BatchSummaryStats)
    case info(title: String, message: String)
    
    // Legacy initializer for backwards compatibility
    public static func batchSummary(processed: Int, errors: Int, duration: TimeInterval) -> NotificationType {
        return .batchSummary(stats: BatchSummaryStats(
            filesMoved: processed,
            errorsEncountered: errors,
            duration: duration
        ))
    }
    
    var isCritical: Bool {
        if case .processingError(_, let critical) = self {
            return critical
        }
        return false
    }
}

/// HUD notification data for display
public struct HUDNotification: Identifiable, Equatable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let icon: String
    public let iconColor: Color
    public let timestamp: Date
    public let playSound: Bool
    
    public static func == (lhs: HUDNotification, rhs: HUDNotification) -> Bool {
        lhs.id == rhs.id
    }
}

/// Manages all app notifications (HUD overlays and system notifications)
@MainActor
public class NotificationManager: ObservableObject {
    public static let shared = NotificationManager()
    
    @Published public var currentHUDNotification: HUDNotification?
    @Published public var hudNotificationQueue: [HUDNotification] = []
    @Published public var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    
    private var settings: NotificationSettingsManager { NotificationSettingsManager.shared }
    private var dismissTask: Task<Void, Never>?
    
    private init() {
        Task {
            await requestSystemNotificationPermission()
            await checkNotificationPermission()
        }
    }
    
    // MARK: - Public API
    
    /// Check current notification permission status
    public func checkNotificationPermission() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationPermissionStatus = settings.authorizationStatus
        }
    }
    
    /// Request notification permission
    public func requestPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            await checkNotificationPermission()
            return granted
        } catch {
            print("NotificationManager: Failed to request permission: \(error)")
            return false
        }
    }
    
    /// Show a notification based on type and user preferences
    public func show(_ type: NotificationType) {
        let settingsValue = settings.settings
        
        // Check if we should show this notification type
        switch type {
        case .processingComplete:
            guard settingsValue.processingComplete else { return }
        case .processingError(_, let isCritical):
            if isCritical && settingsValue.alwaysShowCriticalErrors {
                // Always show critical errors
            } else if !settingsValue.processingErrors {
                return
            }
        case .batchSummary:
            guard settingsValue.batchSummary else { return }
        case .info:
            // Info notifications are always allowed
            break
        }
        
        // Create notification content
        let (title, message, icon, iconColor) = notificationContent(for: type)
        
        // Show in-app HUD if enabled
        if settingsValue.inAppHUD {
            showHUD(title: title, message: message, icon: icon, iconColor: iconColor, playSound: settingsValue.hudSounds)
        }
        
        // Show system notification if enabled
        if settingsValue.systemNotifications {
            Task {
                await showSystemNotification(title: title, message: message, playSound: settingsValue.systemNotificationSounds)
            }
        }
    }
    
    /// Show a simple info notification
    public func showInfo(title: String, message: String) {
        show(.info(title: title, message: message))
    }
    
    /// Show processing complete notification
    public func showProcessingComplete(fileCount: Int, folderName: String) {
        show(.processingComplete(fileCount: fileCount, folderName: folderName))
    }
    
    /// Show processing error notification
    public func showError(message: String, isCritical: Bool = false) {
        show(.processingError(message: message, isCritical: isCritical))
    }
    
    /// Show batch summary notification
    public func showBatchSummary(processed: Int, errors: Int, duration: TimeInterval) {
        show(.batchSummary(processed: processed, errors: errors, duration: duration))
    }
    
    /// Show batch summary notification with detailed stats
    public func showBatchSummary(stats: BatchSummaryStats) {
        show(.batchSummary(stats: stats))
    }
    
    /// Dismiss current HUD notification
    public func dismissHUD() {
        dismissTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) {
            currentHUDNotification = nil
        }
        processQueue()
    }
    
    // MARK: - Private Methods
    
    private func notificationContent(for type: NotificationType) -> (title: String, message: String, icon: String, iconColor: Color) {
        switch type {
        case .processingComplete(let fileCount, let folderName):
            return (
                "Processing Complete",
                "Organized \(fileCount) file\(fileCount == 1 ? "" : "s") in \(folderName)",
                "checkmark.circle.fill",
                .green
            )
        case .processingError(let message, let isCritical):
            return (
                isCritical ? "Critical Error" : "Processing Error",
                message,
                isCritical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                isCritical ? .red : .orange
            )
        case .batchSummary(let stats):
            let durationStr = formatDuration(stats.duration)
            
            // Build a detailed message
            var parts: [String] = []
            
            if stats.filesMoved > 0 {
                parts.append("\(stats.filesMoved) file\(stats.filesMoved == 1 ? "" : "s") moved")
            }
            if stats.foldersCreated > 0 {
                parts.append("\(stats.foldersCreated) folder\(stats.foldersCreated == 1 ? "" : "s") created")
            }
            if stats.filesRenamed > 0 {
                parts.append("\(stats.filesRenamed) renamed")
            }
            if stats.filesTagged > 0 {
                parts.append("\(stats.filesTagged) tagged")
            }
            if stats.duplicatesFound > 0 {
                parts.append("\(stats.duplicatesFound) duplicate\(stats.duplicatesFound == 1 ? "" : "s") found")
            }
            
            // Create the message
            let message: String
            let title: String
            let iconColor: Color
            
            if parts.isEmpty && stats.errorsEncountered == 0 {
                // No operations performed
                message = "No files to organize"
                title = "Organization Complete"
                iconColor = .secondary
            } else if stats.errorsEncountered > 0 {
                let errorSuffix = " with \(stats.errorsEncountered) error\(stats.errorsEncountered == 1 ? "" : "s")"
                if parts.isEmpty {
                    message = "Completed\(errorSuffix) in \(durationStr)"
                } else {
                    message = "\(parts.joined(separator: ", "))\(errorSuffix) (\(durationStr))"
                }
                title = stats.folderName.isEmpty ? "Organization Complete" : "Organized \(stats.folderName)"
                iconColor = .orange
            } else {
                message = "\(parts.joined(separator: ", ")) (\(durationStr))"
                title = stats.folderName.isEmpty ? "Organization Complete" : "Organized \(stats.folderName)"
                iconColor = .green
            }
            
            return (title, message, "folder.fill.badge.gearshape", iconColor)
        case .info(let title, let message):
            return (title, message, "info.circle.fill", .blue)
        }
    }
    
    private func showHUD(title: String, message: String, icon: String, iconColor: Color, playSound: Bool) {
        let notification = HUDNotification(
            title: title,
            message: message,
            icon: icon,
            iconColor: iconColor,
            timestamp: Date(),
            playSound: playSound
        )
        
        if currentHUDNotification == nil {
            presentHUD(notification)
        } else {
            hudNotificationQueue.append(notification)
        }
    }
    
    private func presentHUD(_ notification: HUDNotification) {
        if notification.playSound {
            playHUDSound()
        }
        
        withAnimation(.easeOut(duration: 0.2)) {
            currentHUDNotification = notification
        }
        
        // Auto-dismiss after 4 seconds
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                dismissHUD()
            }
        }
    }
    
    private func processQueue() {
        guard !hudNotificationQueue.isEmpty else { return }
        
        // Small delay before showing next notification
        Task {
            try? await Task.sleep(nanoseconds: 300_000_000)
            if let next = hudNotificationQueue.first {
                hudNotificationQueue.removeFirst()
                presentHUD(next)
            }
        }
    }
    
    private func showSystemNotification(title: String, message: String, playSound: Bool) async {
        // Check permission first
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        
        guard settings.authorizationStatus == .authorized else {
            print("NotificationManager: System notifications not authorized (status: \(settings.authorizationStatus.rawValue))")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if playSound {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("NotificationManager: System notification sent successfully")
        } catch {
            print("NotificationManager: Failed to send system notification: \(error)")
        }
    }
    
    private func requestSystemNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            print("NotificationManager: Permission \(granted ? "granted" : "denied")")
        } catch {
            print("NotificationManager: Permission request failed: \(error)")
        }
    }
    
    private func playHUDSound() {
        // Use a subtle glass sound if available, fallback to beep
        if let glassSound = NSSound(named: "Glass") {
            glassSound.play()
        } else {
            NSSound.beep()
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 60 {
            return "\(Int(duration))s"
        } else if duration < 3600 {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return "\(minutes)m \(seconds)s"
        } else {
            let hours = Int(duration) / 3600
            let minutes = (Int(duration) % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }
}
