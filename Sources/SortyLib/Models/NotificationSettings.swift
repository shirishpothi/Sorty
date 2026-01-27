//
//  NotificationSettings.swift
//  Sorty
//
//  Notification preferences for the app
//

import Foundation

/// Notification backend to use for system notifications
public enum NotificationBackend: String, Codable, CaseIterable, Sendable {
    case native = "native"       // UNUserNotificationCenter (macOS native)
    case notifiCLI = "notificli" // NotifiCLI for actionable/persistent notifications
    
    public var displayName: String {
        switch self {
        case .native: return "Native (macOS)"
        case .notifiCLI: return "NotifiCLI (Enhanced)"
        }
    }
    
    public var description: String {
        switch self {
        case .native: return "Standard macOS notifications via Notification Center"
        case .notifiCLI: return "Actionable, persistent notifications with buttons"
        }
    }
}

/// Notification settings model for user preferences
public struct NotificationSettings: Codable, Equatable {
    // MARK: - Delivery Method
    
    /// Show notifications as subtle bottom-left overlays
    public var inAppHUD: Bool = true
    
    /// Show in macOS Notification Center
    public var systemNotifications: Bool = true
    
    /// Which backend to use for system notifications
    public var notificationBackend: NotificationBackend = .notifiCLI
    
    // MARK: - NotifiCLI Settings
    
    /// Make notifications persistent (stay until dismissed)
    public var persistentNotifications: Bool = true
    
    /// Show action buttons on notifications (Undo, Open Folder, etc.)
    public var showActionButtons: Bool = true
    
    /// Sound to play with NotifiCLI notifications
    public var notifiCLISound: String = "Glass"
    
    /// Custom app icon for notifications (app path or shorthand)
    public var customNotificationIcon: String = ""
    
    // MARK: - Notification Types
    
    /// When file processing finishes successfully
    public var processingComplete: Bool = true
    
    /// When AI has finished generating a plan and it's ready for review
    public var previewReady: Bool = true
    
    /// Show preview ready notification even when app is in foreground
    public var showPreviewReadyInForeground: Bool = true
    
    /// When errors occur during processing
    public var processingErrors: Bool = true
    
    /// Summary notification after processing multiple files
    public var batchSummary: Bool = true
    
    /// Display critical errors even if notifications are off
    public var alwaysShowCriticalErrors: Bool = true
    
    // MARK: - Sounds
    
    /// Play sound with system notifications
    public var systemNotificationSounds: Bool = true
    
    /// Play sound with in-app HUD notifications
    public var hudSounds: Bool = false
    
    /// Play a satisfying "ting" sound when organization completes successfully
    public var playCompletionSound: Bool = true
    
    public init() {}
    
    public static let `default` = NotificationSettings()
}

/// Manager for notification settings
@MainActor
public class NotificationSettingsManager: ObservableObject {
    @Published public var settings: NotificationSettings = .default {
        didSet {
            save()
        }
    }
    
    private let userDefaults = UserDefaults.standard
    private let settingsKey = "notificationSettings"
    
    public static let shared = NotificationSettingsManager()
    
    private init() {
        load()
    }
    
    private func load() {
        if let data = userDefaults.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(NotificationSettings.self, from: data) {
            settings = decoded
        }
    }
    
    private func save() {
        if let encoded = try? JSONEncoder().encode(settings) {
            userDefaults.set(encoded, forKey: settingsKey)
        }
    }
    
    public func reset() {
        settings = .default
    }
}
