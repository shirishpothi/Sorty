//
//  NotificationSettings.swift
//  Sorty
//
//  Notification preferences for the app
//

import Foundation
import Combine

/// Notification settings model for user preferences
public struct NotificationSettings: Codable, Equatable, Sendable {
    // MARK: - Delivery Method
    
    /// Show notifications as subtle bottom-left overlays
    public var inAppHUD: Bool = true
    
    /// Show in macOS Notification Center
    public var systemNotifications: Bool = true
    
    /// Show action buttons on notifications (Undo, Open Folder, etc.)
    public var showActionButtons: Bool = true
    
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

    /// Specifically notify when automatic organization (watched folders) occurs
    public var notifyOnAutoOrganize: Bool = true

    /// Notify when a watched folder begins organizing newly detected files.
    public var notifyOnWatchedFolderStart: Bool?

    /// Notify when a watched folder finishes organizing detected files.
    public var notifyOnWatchedFolderCompletion: Bool?

    public var watchedFolderStartNotificationsEnabled: Bool {
        get { notifyOnWatchedFolderStart ?? notifyOnAutoOrganize }
        set { notifyOnWatchedFolderStart = newValue }
    }

    public var watchedFolderCompletionNotificationsEnabled: Bool {
        get { notifyOnWatchedFolderCompletion ?? notifyOnAutoOrganize }
        set { notifyOnWatchedFolderCompletion = newValue }
    }
    
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

    @MainActor
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
        setupNotificationObservers()
    }

    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.reset()
        }
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
