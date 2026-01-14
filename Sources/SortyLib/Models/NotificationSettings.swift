//
//  NotificationSettings.swift
//  Sorty
//
//  Notification preferences for the app
//

import Foundation

/// Notification settings model for user preferences
public struct NotificationSettings: Codable, Equatable {
    // MARK: - Delivery Method
    
    /// Show notifications as subtle bottom-left overlays
    public var inAppHUD: Bool = true
    
    /// Show in macOS Notification Center
    public var systemNotifications: Bool = true
    
    // MARK: - Notification Types
    
    /// When file processing finishes successfully
    public var processingComplete: Bool = true
    
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
