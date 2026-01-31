//
//  NotificationManager.swift
//  Sorty
//
//  Unified notification manager for HUD and system notifications
//  Supports both native macOS notifications and NotifiCLI for enhanced features
//

import Foundation
import Combine
import SwiftUI
@preconcurrency import UserNotifications
@preconcurrency import AppKit

// MARK: - Notification Names for Actions

public extension NSNotification.Name {
    /// Posted when user clicks "Undo" on a notification
    static let undoLastOrganization = NSNotification.Name("SortyUndoLastOrganization")
    
    /// Posted when user clicks "Retry" on an error notification
    static let retryLastOrganization = NSNotification.Name("SortyRetryLastOrganization")
    
    /// Posted when user clicks "Show Details" on a notification
    static let showOrganizationDetails = NSNotification.Name("SortyShowOrganizationDetails")
    
    /// Posted when user clicks "Open Folder" on a notification
    static let openOrganizedFolder = NSNotification.Name("SortyOpenOrganizedFolder")
}

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
    public let folderPath: String?
    public let canUndo: Bool
    
    public init(
        filesMoved: Int = 0,
        foldersCreated: Int = 0,
        filesRenamed: Int = 0,
        filesTagged: Int = 0,
        duplicatesFound: Int = 0,
        errorsEncountered: Int = 0,
        duration: TimeInterval = 0,
        folderName: String = "",
        folderPath: String? = nil,
        canUndo: Bool = false
    ) {
        self.filesMoved = filesMoved
        self.foldersCreated = foldersCreated
        self.filesRenamed = filesRenamed
        self.filesTagged = filesTagged
        self.duplicatesFound = duplicatesFound
        self.errorsEncountered = errorsEncountered
        self.duration = duration
        self.folderName = folderName
        self.folderPath = folderPath
        self.canUndo = canUndo
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

/// Actions that can be performed from notification buttons
public enum NotificationAction: Sendable {
    case undo
    case openFolder(path: String)
    case showDetails
    case retry
    case dismiss
}

/// Callback type for handling notification actions
public typealias NotificationActionHandler = @Sendable (NotificationAction) async -> Void

    /// Types of notifications the app can show
    public enum NotificationType: Sendable {
        case processingComplete(fileCount: Int, folderName: String, folderPath: String?, canUndo: Bool)
        case previewReady(folderName: String)
        case processingError(message: String, isCritical: Bool, canRetry: Bool)
        case batchSummary(stats: BatchSummaryStats)
        case info(title: String, message: String)
        
        // Legacy initializers for backwards compatibility
        public static func processingComplete(fileCount: Int, folderName: String) -> NotificationType {
            return .processingComplete(fileCount: fileCount, folderName: folderName, folderPath: nil, canUndo: false)
        }
        
        public static func processingError(message: String, isCritical: Bool = false) -> NotificationType {
            return .processingError(message: message, isCritical: isCritical, canRetry: false)
        }
        
        public static func batchSummary(processed: Int, errors: Int, duration: TimeInterval) -> NotificationType {
            return .batchSummary(stats: BatchSummaryStats(
                filesMoved: processed,
                errorsEncountered: errors,
                duration: duration
            ))
        }
        
        var isCritical: Bool {
            if case .processingError(_, let critical, _) = self {
                return critical
            }
            return false
        }
        
        /// Whether the app is currently in the foreground
        @MainActor
        private static var isAppActive: Bool {
            return NSApplication.shared.isActive
        }
        
        /// Should this notification be shown as a system notification?
        @MainActor
        var shouldShowSystem: Bool {
            // Always show if backgrounded or if it's a critical error
            if !Self.isAppActive || isCritical {
                return true
            }
            
            // Check if previewReady should show in foreground
            if case .previewReady = self {
                return NotificationSettingsManager.shared.settings.showPreviewReadyInForeground
            }
            
            // Otherwise, respect user settings for in-app HUD vs system
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
    @Published public var isNotifiCLIAvailable: Bool = false
    @Published public var notifiCLISetupStatus: String = "Initializing..."
    
    private var settings: NotificationSettingsManager { NotificationSettingsManager.shared }
    private var dismissTask: Task<Void, Never>?
    private var notifiCLISetupTask: Task<Void, Never>?
    
    private init() {
        // Start setup immediately
        notifiCLISetupTask = Task {
            await setupNotificationSystem()
        }
    }
    
    /// Check if it's safe to use UNUserNotificationCenter (requires bundle ID and not running in tests)
    private var isSafeToUseSystemNotifications: Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        
        // Avoid running in xctest tool environment which crashes UNUserNotificationCenter with "bundleProxyForCurrentProcess is nil"
        if bundleID == "com.apple.dt.xctest.tool" {
            return false
        }
        
        return true
    }
    
    /// Initialize the notification system (call on app startup for faster first notification)
    private func setupNotificationSystem() async {
        // Request native notification permission
        if isSafeToUseSystemNotifications {
            await requestSystemNotificationPermission()
            await checkNotificationPermission()
        } else {
            print("NotificationManager: Skipping system notification setup (CLI/Test environment)")
            await MainActor.run {
                self.notificationPermissionStatus = .denied
            }
        }
        
        // Setup NotifiCLI in background (builds on first run)
        await MainActor.run {
            self.notifiCLISetupStatus = "Setting up enhanced notifications..."
        }
        
        let available = await NotifiCLIService.shared.ensureSetup()
        
        await MainActor.run {
            self.isNotifiCLIAvailable = available
            self.notifiCLISetupStatus = available ? "Ready" : "Using native notifications"
        }
        
        if available {
            print("NotificationManager: NotifiCLI ready for enhanced notifications")
        } else {
            print("NotificationManager: Using native macOS notifications")
        }
    }
    
    // MARK: - Public API
    
    /// Check if NotifiCLI is installed and available
    public func checkNotifiCLIAvailability() async {
        let available = await NotifiCLIService.shared.checkAvailability()
        await MainActor.run {
            self.isNotifiCLIAvailable = available
        }
    }
    
    /// Ensure NotifiCLI is ready (waits for setup to complete)
    public func ensureReady() async {
        // Wait for initial setup to complete
        await notifiCLISetupTask?.value
    }
    
    /// Get NotifiCLI installation info
    public func getNotifiCLIInfo() async -> (installed: Bool, path: String?) {
        return await NotifiCLIService.shared.getInstallationInfo()
    }
    
    /// Check current notification permission status
    public func checkNotificationPermission() async {
        guard isSafeToUseSystemNotifications else { return }
        
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            self.notificationPermissionStatus = settings.authorizationStatus
        }
    }
    
    /// Request notification permission
    public func requestPermission() async -> Bool {
        guard isSafeToUseSystemNotifications else { return false }
        
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
        
        print("NotificationManager: show() called with type, inAppHUD=\(settingsValue.inAppHUD), systemNotifications=\(settingsValue.systemNotifications)")
        
        // Check if we should show this notification type
        switch type {
        case .processingComplete:
            guard settingsValue.processingComplete else {
                print("NotificationManager: processingComplete notifications disabled")
                return
            }
        case .previewReady:
            guard settingsValue.previewReady else {
                print("NotificationManager: previewReady notifications disabled")
                return
            }
        case .processingError(_, let isCritical, _):
            if isCritical && settingsValue.alwaysShowCriticalErrors {
                // Always show critical errors
            } else if !settingsValue.processingErrors {
                print("NotificationManager: processingErrors notifications disabled")
                return
            }
        case .batchSummary:
            guard settingsValue.batchSummary else {
                print("NotificationManager: batchSummary notifications disabled")
                return
            }
        case .info:
            // Info notifications are always allowed
            break
        }
        
        // Create notification content
        let (title, message, icon, iconColor) = notificationContent(for: type)
        
        // Show in-app HUD if enabled AND app is active
        if settingsValue.inAppHUD && NSApplication.shared.isActive {
            showHUD(title: title, message: message, icon: icon, iconColor: iconColor, playSound: settingsValue.hudSounds)
        } else {
            print("NotificationManager: skipping HUD (inAppHUD=\(settingsValue.inAppHUD), isActive=\(NSApplication.shared.isActive))")
        }
        
        // Show system notification if enabled AND (app is backgrounded OR it's critical)
        let shouldShowSystem = type.shouldShowSystem
        if settingsValue.systemNotifications && shouldShowSystem {
            Task {
                await showSystemNotification(
                    type: type,
                    title: title,
                    message: message,
                    playSound: settingsValue.systemNotificationSounds
                )
            }
        } else {
            print("NotificationManager: skipping system notification (enabled=\(settingsValue.systemNotifications), shouldShow=\(shouldShowSystem))")
        }
    }
    
    /// Show a notification with a custom action handler
    public func show(_ type: NotificationType, actionHandler: @escaping NotificationActionHandler) {
        let settingsValue = settings.settings
        
        // Create notification content
        let (title, message, icon, iconColor) = notificationContent(for: type)
        
        // Show in-app HUD if enabled AND app is active
        if settingsValue.inAppHUD && NSApplication.shared.isActive {
            showHUD(title: title, message: message, icon: icon, iconColor: iconColor, playSound: settingsValue.hudSounds)
        }
        
        // Show system notification if enabled AND (app is backgrounded OR it's critical)
        if settingsValue.systemNotifications && type.shouldShowSystem {
            Task {
                await showSystemNotification(
                    type: type,
                    title: title,
                    message: message,
                    playSound: settingsValue.systemNotificationSounds,
                    actionHandler: actionHandler
                )
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
    
    /// Show processing complete notification with folder path and undo support
    public func showProcessingComplete(
        fileCount: Int,
        folderName: String,
        folderPath: String?,
        canUndo: Bool = false,
        onAction: NotificationActionHandler? = nil
    ) {
        let type = NotificationType.processingComplete(
            fileCount: fileCount,
            folderName: folderName,
            folderPath: folderPath,
            canUndo: canUndo
        )
        if let handler = onAction {
            show(type, actionHandler: handler)
        } else {
            show(type)
        }
    }
    
    /// Show processing error notification
    public func showError(message: String, isCritical: Bool = false) {
        show(.processingError(message: message, isCritical: isCritical))
    }
    
    /// Show processing error notification with retry option
    public func showError(
        message: String,
        isCritical: Bool = false,
        canRetry: Bool = false,
        onAction: NotificationActionHandler? = nil
    ) {
        let type = NotificationType.processingError(
            message: message,
            isCritical: isCritical,
            canRetry: canRetry
        )
        if let handler = onAction {
            show(type, actionHandler: handler)
        } else {
            show(type)
        }
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
        case .processingComplete(let fileCount, let folderName, _, _):
            return (
                "Processing Complete",
                "Organized \(fileCount) file\(fileCount == 1 ? "" : "s") in \(folderName)",
                "checkmark.circle.fill",
                .green
            )
        case .previewReady(let folderName):
            return (
                "Preview Ready",
                "Your organization preview for \(folderName) is ready to review",
                "eye.fill",
                .blue
            )
        case .processingError(let message, let isCritical, _):
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
        print("NotificationManager: showHUD called - title: \(title), message: \(message)")
        
        let notification = HUDNotification(
            title: title,
            message: message,
            icon: icon,
            iconColor: iconColor,
            timestamp: Date(),
            playSound: playSound
        )
        
        if currentHUDNotification == nil {
            print("NotificationManager: Presenting HUD immediately")
            presentHUD(notification)
        } else {
            print("NotificationManager: Queuing HUD notification (queue size: \(hudNotificationQueue.count + 1))")
            hudNotificationQueue.append(notification)
        }
    }
    
    private func presentHUD(_ notification: HUDNotification) {
        print("NotificationManager: presentHUD - \(notification.title)")
        
        if notification.playSound {
            playHUDSound()
        }
        
        withAnimation(.easeOut(duration: 0.2)) {
            currentHUDNotification = notification
        }
        
        // Force publish change for observers
        objectWillChange.send()
        
        print("NotificationManager: currentHUDNotification set, scheduling auto-dismiss")
        
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
        await showSystemNotification(
            type: .info(title: title, message: message),
            title: title,
            message: message,
            playSound: playSound
        )
    }
    
    private func showSystemNotification(
        type: NotificationType,
        title: String,
        message: String,
        playSound: Bool,
        actionHandler: NotificationActionHandler? = nil
    ) async {
        let settingsValue = settings.settings
        
        // Determine which backend to use
        switch settingsValue.notificationBackend {
        case .notifiCLI:
            await showNotifiCLINotification(
                type: type,
                title: title,
                message: message,
                playSound: playSound,
                actionHandler: actionHandler
            )
        case .native:
            await showNativeNotification(title: title, message: message, playSound: playSound)
        }
    }
    
    /// Show notification using NotifiCLI with action buttons
    private func showNotifiCLINotification(
        type: NotificationType,
        title: String,
        message: String,
        playSound: Bool,
        actionHandler: NotificationActionHandler?
    ) async {
        let settingsValue = settings.settings
        
        // Build actions based on notification type and settings
        var actions: [String] = []
        var folderPath: String? = nil
        var canUndo = false
        var canRetry = false
        
        if settingsValue.showActionButtons {
            switch type {
            case .processingComplete(_, _, let path, let undo):
                folderPath = path
                canUndo = undo
                if undo {
                    actions.append("Undo")
                }
                if let _ = path {
                    actions.append("Open Folder")
                }
                actions.append("Dismiss")
                
            case .processingError(_, _, let retry):
                canRetry = retry
                if retry {
                    actions.append("Retry")
                }
                actions.append("Show Details")
                actions.append("Dismiss")
                
            case .batchSummary(let stats):
                folderPath = stats.folderPath
                canUndo = stats.canUndo
                if stats.canUndo {
                    actions.append("Undo All")
                }
                if let _ = stats.folderPath {
                    actions.append("Open Folder")
                }
                if stats.hasErrors {
                    actions.append("Show Details")
                }
                actions.append("Dismiss")
                
            case .info:
                // Simple info notifications don't need action buttons
                break
                
            case .previewReady:
                actions.append("Review")
                actions.append("Dismiss")
            }
        }
        
        // Build NotifiCLI config
        let config = NotifiCLIConfig(
            title: title,
            message: message,
            actions: actions.isEmpty ? nil : actions,
            icon: settingsValue.customNotificationIcon.isEmpty ? nil : settingsValue.customNotificationIcon,
            sound: playSound ? settingsValue.notifiCLISound : nil,
            persistent: settingsValue.persistentNotifications && !actions.isEmpty
        )
        
        // Send notification and handle response
        let response = await NotifiCLIService.shared.send(config)
        
        print("NotificationManager: NotifiCLI response: \(response)")
        
        // Handle the response
        await handleNotifiCLIResponse(
            response,
            folderPath: folderPath,
            canUndo: canUndo,
            canRetry: canRetry,
            actionHandler: actionHandler
        )
    }
    
    /// Handle response from NotifiCLI notification
    private func handleNotifiCLIResponse(
        _ response: NotifiCLIResponse,
        folderPath: String?,
        canUndo: Bool,
        canRetry: Bool,
        actionHandler: NotificationActionHandler?
    ) async {
        switch response {
        case .action(let actionLabel):
            switch actionLabel {
            case "Undo", "Undo All":
                if canUndo {
                    await actionHandler?(.undo)
                    // Post notification for undo action
                    NotificationCenter.default.post(name: .undoLastOrganization, object: nil)
                }
                
            case "Open Folder":
                if let path = folderPath {
                    await actionHandler?(.openFolder(path: path))
                    // Post notification for open folder action
                    NotificationCenter.default.post(
                        name: .openOrganizedFolder,
                        object: nil,
                        userInfo: ["folderPath": path]
                    )
                    // Open folder in Finder
                    let url = URL(fileURLWithPath: path)
                    NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
                }
                
            case "Show Details":
                await actionHandler?(.showDetails)
                // Post notification to show details
                NotificationCenter.default.post(name: .showOrganizationDetails, object: nil)
                
            case "Retry":
                if canRetry {
                    await actionHandler?(.retry)
                    // Post notification for retry
                    NotificationCenter.default.post(name: .retryLastOrganization, object: nil)
                }
                
            case "Dismiss":
                await actionHandler?(.dismiss)
                
            default:
                // Unknown action, treat as custom action
                print("NotificationManager: Unknown action: \(actionLabel)")
            }
            
        case .defaultClick:
            // User clicked the notification body - open folder if available
            if let path = folderPath {
                let url = URL(fileURLWithPath: path)
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
            }
            
        case .dismissed, .timeout:
            // User dismissed or notification timed out
            break
            
        case .reply(let text):
            // Reply text received (not typically used for our notifications)
            print("NotificationManager: Received reply: \(text)")
            
        case .error(let error):
            print("NotificationManager: NotifiCLI error: \(error)")
            // Fall back to native notification
            await showNativeNotification(title: "Notification Error", message: error, playSound: false)
        }
    }
    
    /// Show notification using native macOS UNUserNotificationCenter (fallback)
    private func showNativeNotification(title: String, message: String, playSound: Bool) async {
        guard isSafeToUseSystemNotifications else {
            print("NotificationManager: Skipping native notification (CLI/Test environment)")
            return
        }
        
        // Check permission first
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        
        guard notificationSettings.authorizationStatus == .authorized else {
            print("NotificationManager: System notifications not authorized (status: \(notificationSettings.authorizationStatus.rawValue))")
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if playSound {
            content.sound = .default
        }
        
        // Attach app icon to ensure it displays in the notification
        if let iconAttachment = NotificationManager.createAppIconAttachment() {
            content.attachments = [iconAttachment]
        }
        
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("NotificationManager: Native system notification sent successfully")
        } catch {
            print("NotificationManager: Failed to send system notification: \(error)")
        }
    }
    
    private func requestSystemNotificationPermission() async {
        guard isSafeToUseSystemNotifications else { return }
        
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
    
    /// Creates a notification attachment for the app icon to ensure it displays in notifications
    /// - Returns: A UNNotificationAttachment for the app icon, or nil if unavailable
    public static func createAppIconAttachment() -> UNNotificationAttachment? {
        guard let iconImage = NSImage(named: "AppIcon") ?? NSApp.applicationIconImage else {
            return nil
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let iconURL = tempDir.appendingPathComponent("SortyNotificationIcon-\(UUID().uuidString).png")
        
        guard let tiffData = iconImage.tiffRepresentation,
              let bitmapRep = NSBitmapImageRep(data: tiffData),
              let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        
        do {
            try pngData.write(to: iconURL)
            let attachment = try UNNotificationAttachment(
                identifier: "appIcon",
                url: iconURL,
                options: [UNNotificationAttachmentOptionsTypeHintKey: "public.png"]
            )
            return attachment
        } catch {
            try? FileManager.default.removeItem(at: iconURL)
            return nil
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
