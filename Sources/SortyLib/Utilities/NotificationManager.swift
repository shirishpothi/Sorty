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

private enum NativeNotificationCategory {
    static let processingComplete = "SORTY_PROCESSING_COMPLETE"
    static let processingError = "SORTY_PROCESSING_ERROR"
    static let batchSummary = "SORTY_BATCH_SUMMARY"
    static let previewReady = "SORTY_PREVIEW_READY"
}

private enum NativeNotificationActionIdentifier {
    static let undo = "SORTY_UNDO"
    static let undoAll = "SORTY_UNDO_ALL"
    static let openFolder = "SORTY_OPEN_FOLDER"
    static let retry = "SORTY_RETRY"
    static let showDetails = "SORTY_SHOW_DETAILS"
    static let review = "SORTY_REVIEW"
}

private enum NativeNotificationUserInfoKey {
    static let folderPath = "folderPath"
}

private final class NativeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleNativeNotificationResponse(response)
        }
        completionHandler()
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        var options: UNNotificationPresentationOptions = [.banner]
        if notification.request.content.sound != nil {
            options.insert(.sound)
        }
        completionHandler(options)
    }
}

    /// Types of notifications the app can show
    public enum NotificationType: Sendable {
        case processingComplete(fileCount: Int, folderName: String, folderPath: String?, canUndo: Bool, isAutomated: Bool = false)
        case previewReady(folderName: String)
        case processingError(message: String, isCritical: Bool, canRetry: Bool, isAutomated: Bool = false)
        case batchSummary(stats: BatchSummaryStats, isAutomated: Bool = false)
        case info(title: String, message: String)
        
        // Legacy initializers for backwards compatibility
        public static func processingComplete(fileCount: Int, folderName: String) -> NotificationType {
            return .processingComplete(fileCount: fileCount, folderName: folderName, folderPath: nil, canUndo: false, isAutomated: false)
        }
        
        public static func processingError(message: String, isCritical: Bool = false) -> NotificationType {
            return .processingError(message: message, isCritical: isCritical, canRetry: false, isAutomated: false)
        }
        
        public static func batchSummary(processed: Int, errors: Int, duration: TimeInterval) -> NotificationType {
            return .batchSummary(stats: BatchSummaryStats(
                filesMoved: processed,
                errorsEncountered: errors,
                duration: duration
            ), isAutomated: false)
        }
        
        var isCritical: Bool {
            if case .processingError(_, let critical, _, _) = self {
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
    private var permissionCached: Bool = false
    private let nativeNotificationDelegate = NativeNotificationDelegate()
    private var pendingNativeActionHandlers: [String: NotificationActionHandler] = [:]
    
    private init() {
        if isSafeToUseSystemNotifications {
            UNUserNotificationCenter.current().delegate = nativeNotificationDelegate
            registerNativeNotificationCategories()
        }
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
        if isSafeToUseSystemNotifications {
            await MainActor.run {
                self.notifiCLISetupStatus = "Setting up enhanced notifications..."
            }
            
            let available = await NotifiCLIService.shared.ensureSetup()
            
            await MainActor.run {
                self.isNotifiCLIAvailable = available
                self.notifiCLISetupStatus = available ? "Ready" : "Using native notifications"
            }
        } else {
            await MainActor.run {
                self.notifiCLISetupStatus = "Notifications disabled in this environment"
                self.isNotifiCLIAvailable = false
            }
        }
        
        if isSafeToUseSystemNotifications && isNotifiCLIAvailable {
            print("NotificationManager: NotifiCLI ready for enhanced notifications")
        } else if isSafeToUseSystemNotifications {
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
        
        // Handle automated organization filter
        switch type {
        case .processingComplete(_, _, _, _, let isAutomated),
             .batchSummary(_, let isAutomated):
            if isAutomated && !settingsValue.notifyOnAutoOrganize {
                print("NotificationManager: Automated organization notification suppressed by settings")
                return
            }
        case .processingError(_, _, _, let isAutomated):
            if isAutomated && !settingsValue.notifyOnAutoOrganize && !type.isCritical {
                print("NotificationManager: Automated organization error suppressed by settings")
                return
            }
        default:
            break
        }
        
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
        case .processingError(_, let isCritical, _, _):
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
        
        // Show system notification: always for critical errors, otherwise when enabled + shouldShow
        let isCriticalError = type.isCritical
        let isAppBackgrounded = !NSApplication.shared.isActive
        let shouldShowSystem = type.shouldShowSystem
        
        // Request user attention (dock bounce) for critical errors and key background events
        if shouldRequestAttention(for: type, isAppBackgrounded: isAppBackgrounded) {
            requestAttention(isCritical: isCriticalError)
        }
        
        if isCriticalError || (settingsValue.systemNotifications && (shouldShowSystem || isAppBackgrounded)) {
            Task {
                await showSystemNotification(
                    type: type,
                    title: title,
                    message: message,
                    playSound: settingsValue.systemNotificationSounds
                )
            }
        } else {
            print("NotificationManager: skipping system notification (enabled=\(settingsValue.systemNotifications), shouldShow=\(shouldShowSystem), critical=\(isCriticalError))")
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
        
        // Show system notification: always for critical errors, otherwise when enabled + shouldShow or backgrounded
        let isCriticalError = type.isCritical
        let isAppBackgrounded = !NSApplication.shared.isActive

        if shouldRequestAttention(for: type, isAppBackgrounded: isAppBackgrounded) {
            requestAttention(isCritical: isCriticalError)
        }
        
        if isCriticalError || (settingsValue.systemNotifications && (type.shouldShowSystem || isAppBackgrounded)) {
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
        isAutomated: Bool = false,
        onAction: NotificationActionHandler? = nil
    ) {
        let type = NotificationType.processingComplete(
            fileCount: fileCount,
            folderName: folderName,
            folderPath: folderPath,
            canUndo: canUndo,
            isAutomated: isAutomated
        )
        if let handler = onAction {
            show(type, actionHandler: handler)
        } else {
            show(type)
        }
    }
    
    /// Show processing error notification
    public func showError(message: String, isCritical: Bool = false) {
        show(.processingError(message: message, isCritical: isCritical, canRetry: false, isAutomated: false))
    }
    
    /// Show processing error notification with retry option
    public func showError(
        message: String,
        isCritical: Bool = false,
        canRetry: Bool = false,
        isAutomated: Bool = false,
        onAction: NotificationActionHandler? = nil
    ) {
        let type = NotificationType.processingError(
            message: message,
            isCritical: isCritical,
            canRetry: canRetry,
            isAutomated: isAutomated
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
    public func showBatchSummary(stats: BatchSummaryStats, isAutomated: Bool = false) {
        show(.batchSummary(stats: stats, isAutomated: isAutomated))
    }
    
    /// Request user attention (dock bounce)
    public func requestAttention(isCritical: Bool = false) {
        let requestType: NSApplication.RequestUserAttentionType = isCritical ? .criticalRequest : .informationalRequest
        guard let app = NSApp else { return }
        app.requestUserAttention(requestType)
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
        case .processingComplete(let fileCount, let folderName, _, _, _):
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
        case .processingError(let message, let isCritical, _, _):
            return (
                isCritical ? "Critical Error" : "Processing Error",
                message,
                isCritical ? "xmark.octagon.fill" : "exclamationmark.triangle.fill",
                isCritical ? .red : .orange
            )
        case .batchSummary(let stats, _):
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

    private func shouldRequestAttention(for type: NotificationType, isAppBackgrounded: Bool) -> Bool {
        if type.isCritical {
            return true
        }

        guard isAppBackgrounded else {
            return false
        }

        switch type {
        case .processingComplete, .previewReady, .batchSummary:
            return true
        case .processingError, .info:
            return false
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
        
        switch settingsValue.notificationBackend {
        case .notifiCLI:
            if isNotifiCLIAvailable {
                await showNotifiCLINotification(
                    type: type,
                    title: title,
                    message: message,
                    playSound: playSound,
                    actionHandler: actionHandler
                )
            } else {
                print("NotificationManager: NotifiCLI unavailable, falling back to native")
                await showNativeNotification(
                    type: type,
                    title: title,
                    message: message,
                    playSound: playSound,
                    actionHandler: actionHandler
                )
            }
        case .native:
            await showNativeNotification(
                type: type,
                title: title,
                message: message,
                playSound: playSound,
                actionHandler: actionHandler
            )
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
            case .processingComplete(_, _, let path, let undo, _):
                folderPath = path
                canUndo = undo
                if undo {
                    actions.append("Undo")
                }
                if let _ = path {
                    actions.append("Open Folder")
                }
                actions.append("Dismiss")
                
            case .processingError(_, _, let retry, _):
                canRetry = retry
                if retry {
                    actions.append("Retry")
                }
                actions.append("Show Details")
                actions.append("Dismiss")
                
            case .batchSummary(let stats, _):
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
        await showNativeNotification(
            type: .info(title: title, message: message),
            title: title,
            message: message,
            playSound: playSound,
            actionHandler: nil
        )
    }

    /// Show notification using native macOS UNUserNotificationCenter (fallback)
    private func showNativeNotification(
        type: NotificationType,
        title: String,
        message: String,
        playSound: Bool,
        actionHandler: NotificationActionHandler?
    ) async {
        guard isSafeToUseSystemNotifications else {
            print("NotificationManager: Skipping native notification (CLI/Test environment)")
            return
        }
        
        let notificationSettings = await UNUserNotificationCenter.current().notificationSettings()
        var status = notificationSettings.authorizationStatus
        
        if status == .notDetermined {
            await requestSystemNotificationPermission()
            let updatedSettings = await UNUserNotificationCenter.current().notificationSettings()
            status = updatedSettings.authorizationStatus
        }
        
        guard status == .authorized else {
            print("NotificationManager: System notifications not authorized (status: \(status.rawValue)), trying NotifiCLI fallback")
            if await NotifiCLIService.shared.checkAvailability() {
                let config = NotifiCLIConfig(title: title, message: message)
                _ = await NotifiCLIService.shared.send(config)
            }
            return
        }
        
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message
        if playSound {
            content.sound = .default
        }

        if let categoryIdentifier = nativeCategoryIdentifier(for: type) {
            content.categoryIdentifier = categoryIdentifier
        }

        let userInfo = nativeUserInfo(for: type)
        if !userInfo.isEmpty {
            content.userInfo = userInfo
        }
        
        if let iconAttachment = NotificationManager.createAppIconAttachment() {
            content.attachments = [iconAttachment]
        }
        
        let requestIdentifier = UUID().uuidString
        let request = UNNotificationRequest(
            identifier: requestIdentifier,
            content: content,
            trigger: nil
        )

        if let actionHandler = actionHandler {
            pendingNativeActionHandlers[requestIdentifier] = actionHandler
        }
        
        do {
            try await UNUserNotificationCenter.current().add(request)
            print("NotificationManager: Native system notification sent successfully")
        } catch {
            print("NotificationManager: Failed to send system notification: \(error), trying NotifiCLI fallback")
            if await NotifiCLIService.shared.checkAvailability() {
                let config = NotifiCLIConfig(title: title, message: message)
                _ = await NotifiCLIService.shared.send(config)
            }
        }
    }

    private func nativeCategoryIdentifier(for type: NotificationType) -> String? {
        let settingsValue = settings.settings
        guard settingsValue.showActionButtons else { return nil }

        switch type {
        case .processingComplete(_, _, let folderPath, let canUndo, _):
            guard canUndo || folderPath != nil else { return nil }
            return NativeNotificationCategory.processingComplete
        case .processingError(_, _, let canRetry, _):
            guard canRetry else { return NativeNotificationCategory.processingError }
            return NativeNotificationCategory.processingError
        case .batchSummary(let stats, _):
            guard stats.canUndo || stats.folderPath != nil || stats.hasErrors else { return nil }
            return NativeNotificationCategory.batchSummary
        case .previewReady:
            return NativeNotificationCategory.previewReady
        case .info:
            return nil
        }
    }

    private func nativeUserInfo(for type: NotificationType) -> [AnyHashable: Any] {
        switch type {
        case .processingComplete(_, _, let folderPath, _, _):
            if let path = folderPath {
                return [NativeNotificationUserInfoKey.folderPath: path]
            }
        case .batchSummary(let stats, _):
            if let path = stats.folderPath {
                return [NativeNotificationUserInfoKey.folderPath: path]
            }
        default:
            break
        }
        return [:]
    }

    private func registerNativeNotificationCategories() {
        let undoAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.undo,
            title: "Undo",
            options: [.foreground]
        )
        let undoAllAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.undoAll,
            title: "Undo All",
            options: [.foreground]
        )
        let openFolderAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.openFolder,
            title: "Open Folder",
            options: [.foreground]
        )
        let retryAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.retry,
            title: "Retry",
            options: [.foreground]
        )
        let showDetailsAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.showDetails,
            title: "Show Details",
            options: [.foreground]
        )
        let reviewAction = UNNotificationAction(
            identifier: NativeNotificationActionIdentifier.review,
            title: "Review",
            options: [.foreground]
        )

        let processingComplete = UNNotificationCategory(
            identifier: NativeNotificationCategory.processingComplete,
            actions: [undoAction, openFolderAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let processingError = UNNotificationCategory(
            identifier: NativeNotificationCategory.processingError,
            actions: [retryAction, showDetailsAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let batchSummary = UNNotificationCategory(
            identifier: NativeNotificationCategory.batchSummary,
            actions: [undoAllAction, openFolderAction, showDetailsAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )
        let previewReady = UNNotificationCategory(
            identifier: NativeNotificationCategory.previewReady,
            actions: [reviewAction],
            intentIdentifiers: [],
            options: [.customDismissAction]
        )

        UNUserNotificationCenter.current().setNotificationCategories([
            processingComplete,
            processingError,
            batchSummary,
            previewReady
        ])
    }

    func handleNativeNotificationResponse(_ response: UNNotificationResponse) {
        let identifier = response.notification.request.identifier
        let userInfo = response.notification.request.content.userInfo
        let folderPath = userInfo[NativeNotificationUserInfoKey.folderPath] as? String
        let actionHandler = pendingNativeActionHandlers.removeValue(forKey: identifier)

        switch response.actionIdentifier {
        case UNNotificationDefaultActionIdentifier:
            if let path = folderPath {
                NotificationCenter.default.post(
                    name: .openOrganizedFolder,
                    object: nil,
                    userInfo: [NativeNotificationUserInfoKey.folderPath: path]
                )
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                Task { await actionHandler?(.openFolder(path: path)) }
            } else {
                NotificationCenter.default.post(name: .showOrganizationDetails, object: nil)
                Task { await actionHandler?(.showDetails) }
            }

        case UNNotificationDismissActionIdentifier:
            Task { await actionHandler?(.dismiss) }

        case NativeNotificationActionIdentifier.undo, NativeNotificationActionIdentifier.undoAll:
            NotificationCenter.default.post(name: .undoLastOrganization, object: nil)
            Task { await actionHandler?(.undo) }

        case NativeNotificationActionIdentifier.openFolder:
            if let path = folderPath {
                NotificationCenter.default.post(
                    name: .openOrganizedFolder,
                    object: nil,
                    userInfo: [NativeNotificationUserInfoKey.folderPath: path]
                )
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: path)
                Task { await actionHandler?(.openFolder(path: path)) }
            }

        case NativeNotificationActionIdentifier.retry:
            NotificationCenter.default.post(name: .retryLastOrganization, object: nil)
            Task { await actionHandler?(.retry) }

        case NativeNotificationActionIdentifier.showDetails,
             NativeNotificationActionIdentifier.review:
            NotificationCenter.default.post(name: .showOrganizationDetails, object: nil)
            Task { await actionHandler?(.showDetails) }

        default:
            break
        }
    }
    
    private func requestSystemNotificationPermission() async {
        guard isSafeToUseSystemNotifications else { return }
        guard !permissionCached else { return }
        
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            permissionCached = true
            await MainActor.run {
                self.notificationPermissionStatus = granted ? .authorized : .denied
            }
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
