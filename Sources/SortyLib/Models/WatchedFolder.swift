//
//  WatchedFolder.swift
//  Sorty
//
//  Model for folders being monitored for automatic organization
//

import Foundation
import Combine

public extension Notification.Name {
    static let autoOrganizeDisabledGlobally = Notification.Name("autoOrganizeDisabledGlobally")
}

public enum FolderAccessStatus: String, Codable, Sendable {
    case valid
    case stale
    case lost
    case unknown
}

public struct WatchedFolder: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var path: String
    public var name: String
    public var isEnabled: Bool
    public var autoOrganize: Bool
    public var lastTriggered: Date?
    public var triggerDelay: TimeInterval // Seconds to wait after file changes before organizing
    public var customPrompt: String?
    public var temperature: Double?
    public var bookmarkData: Data?
    public var accessStatus: FolderAccessStatus = .unknown
    public var modelOverride: String?           // nil = use global automation model
    public var providerOverride: AIProvider?    // nil = use global automation provider
    
    public init(
        id: UUID = UUID(),
        path: String,
        name: String? = nil,
        isEnabled: Bool = true,
        autoOrganize: Bool = true,
        lastTriggered: Date? = nil,
        triggerDelay: TimeInterval = 5.0,
        customPrompt: String? = nil,
        temperature: Double? = nil,
        bookmarkData: Data? = nil,
        modelOverride: String? = nil,
        providerOverride: AIProvider? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.isEnabled = isEnabled
        self.autoOrganize = autoOrganize
        self.lastTriggered = lastTriggered
        self.triggerDelay = triggerDelay
        self.customPrompt = customPrompt
        self.temperature = temperature
        self.bookmarkData = bookmarkData
        self.modelOverride = modelOverride
        self.providerOverride = providerOverride
    }
    
    public var url: URL {
        URL(fileURLWithPath: path)
    }
    
    public var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Manager for persisting watched folders
@MainActor
public class WatchedFoldersManager: ObservableObject {
    @Published public private(set) var folders: [WatchedFolder] = []
    @Published public private(set) var limitMessage: String?
    private let userDefaults = UserDefaults.standard
    private let storageKey = "watchedFolders"
    private var activeSecurityScopedURLs: [UUID: URL] = [:]
    
    public init() {
        loadFolders()
        applyEntitlementPolicy(EntitlementRuntime.currentSnapshot)
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.clearAll()
        }
    }
    
    public var maxAllowedFolders: Int {
        EntitlementRuntime.currentSnapshot.maxWatchedFolders
    }

    public var isAtFolderLimit: Bool {
        maxAllowedFolders != .max && folders.count >= maxAllowedFolders
    }

    @discardableResult
    public func addFolder(_ folder: WatchedFolder) -> Bool {
        // Avoid duplicates
        let normalizedPath = Self.normalizedPath(folder.path)
        guard !folders.contains(where: { Self.normalizedPath($0.path) == normalizedPath }) else { return false }
        guard !isAtFolderLimit else {
            limitMessage = ProductCapability.multipleWatchedFolders.unlockSummary
            return false
        }
        var normalizedFolder = folder
        normalizedFolder.autoOrganize = normalizedFolder.isEnabled
        folders.append(sanitized(normalizedFolder, snapshot: EntitlementRuntime.currentSnapshot))
        limitMessage = nil
        saveFolders()
        return true
    }

    public func clearAll() {
        stopAllSecurityScopedAccess()
        folders.removeAll()
        limitMessage = nil
        userDefaults.removeObject(forKey: storageKey)
    }
    
    public func removeFolder(_ folder: WatchedFolder) {
        stopSecurityScopedAccess(for: folder.id)
        folders.removeAll { $0.id == folder.id }
        if maxAllowedFolders == .max || folders.count < maxAllowedFolders {
            limitMessage = nil
        }
        saveFolders()
    }
    
    public func updateFolder(_ folder: WatchedFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            var normalizedFolder = folder
            normalizedFolder.autoOrganize = normalizedFolder.isEnabled
            folders[index] = sanitized(normalizedFolder, snapshot: EntitlementRuntime.currentSnapshot)
            saveFolders()
        }
    }

    public func clearLimitMessage() {
        limitMessage = nil
    }

    public func applyEntitlementPolicy(_ snapshot: EntitlementSnapshot) {
        guard snapshot.state != .unknown else { return }

        var enabledSlotsUsed = 0
        let sanitizedFolders = folders.map { folder in
            var updated = sanitized(folder, snapshot: snapshot)
            if updated.isEnabled {
                enabledSlotsUsed += 1
                if snapshot.maxWatchedFolders != .max,
                   enabledSlotsUsed > snapshot.maxWatchedFolders {
                    updated.isEnabled = false
                    updated.autoOrganize = false
                }
            }
            return updated
        }

        limitMessage = snapshot.maxWatchedFolders != .max && folders.count > snapshot.maxWatchedFolders
            ? ProductCapability.multipleWatchedFolders.unlockSummary
            : nil

        guard sanitizedFolders != folders else { return }
        folders = sanitizedFolders
        saveFolders()
    }
    
    public func toggleEnabled(for folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.isEnabled.toggle()
            updated.autoOrganize = updated.isEnabled
            updateFolder(updated)
        }
    }
    
    public func markTriggered(_ folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.lastTriggered = Date()
            updateFolder(updated)
        }
    }
    
    /// Disables auto-organize for all folders when AI provider becomes invalid
    public func disableAutoOrganizeForAll(reason: String) {
        var hasChanges = false
        var updatedFolders = folders
        
        for (index, folder) in folders.enumerated() {
            if folder.isEnabled {
                updatedFolders[index].isEnabled = false
                updatedFolders[index].autoOrganize = false
                hasChanges = true
            }
        }
        
        if hasChanges {
            folders = updatedFolders
            saveFolders()
            
            // Post notification for user feedback
            NotificationCenter.default.post(
                name: .autoOrganizeDisabledGlobally,
                object: nil,
                userInfo: ["reason": reason]
            )
        }
    }
    
    /// Restores access to all security-scoped bookmarks
    /// Should be called on app launch
    public func restoreSecurityScopedAccess() {
        var updatedFolders = folders
        var hasChanges = false
        
        for (index, folder) in folders.enumerated() {
            guard let bookmarkData = folder.bookmarkData else {
                continue
            }
            
            var isStale = false
            do {
                stopSecurityScopedAccess(for: folder.id)
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
                
                if url.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURLs[folder.id] = url
                    // Success!
                    if isStale {
                         // Recreate bookmark
                         if let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                             updatedFolders[index].bookmarkData = newData
                             hasChanges = true
                         }
                         updatedFolders[index].accessStatus = .stale
                    } else {
                        updatedFolders[index].accessStatus = .valid
                    }
                    
                    // Update path if it changed (e.g. volume rename)
                    if url.path != folder.path {
                        updatedFolders[index].path = url.path
                        hasChanges = true
                    }
                } else {
                    DebugLogger.log("Failed to access security resource for \(folder.name)")
                    updatedFolders[index].accessStatus = .lost
                    hasChanges = true
                }
            } catch {
                DebugLogger.log("Failed to resolve bookmark for \(folder.name): \(error)")
                updatedFolders[index].accessStatus = .lost
                hasChanges = true
            }
        }
        
        if hasChanges {
            folders = updatedFolders
            saveFolders()
        }

        applyEntitlementPolicy(EntitlementRuntime.currentSnapshot)
    }
    
    /// Re-authorizes a watched folder by creating a new security-scoped bookmark from a freshly-picked URL
    public func reauthorizeFolder(_ folder: WatchedFolder, with url: URL) {
        // For URLs from fileImporter, startAccessingSecurityScopedResource()
        // may return false because the picker already grants temporary access.
        // We proceed with bookmark creation regardless.
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let newBookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            // Immediately resolve and activate the new bookmark so the folder
            // is usable in the current session without requiring an app restart.
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: newBookmarkData,
                                          options: .withSecurityScope,
                                          relativeTo: nil,
                                          bookmarkDataIsStale: &isStale) {
                // Start accessing the resolved bookmark URL. We intentionally
                // do NOT stop this access — it must remain active for the
                // watched folder to function until the app quits.
                stopSecurityScopedAccess(for: folder.id)
                if resolvedURL.startAccessingSecurityScopedResource() {
                    activeSecurityScopedURLs[folder.id] = resolvedURL
                }
            }

            var updated = folder
            updated.bookmarkData = newBookmarkData
            updated.path = url.path
            updated.accessStatus = .valid
            updateFolder(updated)

            DebugLogger.log("Successfully reauthorized watched folder: \(folder.name)")
        } catch {
            DebugLogger.log("Failed to create bookmark during reauthorization: \(error)")
        }
    }

    private func loadFolders() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([WatchedFolder].self, from: data) {
            folders = decoded.map { folder in
                var migrated = folder
                migrated.autoOrganize = migrated.isEnabled
                return migrated
            }
            saveFolders()
        }
    }

    private func sanitized(_ folder: WatchedFolder, snapshot: EntitlementSnapshot) -> WatchedFolder {
        var sanitizedFolder = folder
        if !snapshot.allowsParameterTuning {
            sanitizedFolder.temperature = EntitlementSnapshot.defaultLockedTemperature
        }
        if !snapshot.allowsAutomationSeparateModelSelection {
            sanitizedFolder.modelOverride = nil
            sanitizedFolder.providerOverride = nil
        }
        return sanitizedFolder
    }
    
    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }

    private func stopSecurityScopedAccess(for id: UUID) {
        guard let url = activeSecurityScopedURLs.removeValue(forKey: id) else { return }
        url.stopAccessingSecurityScopedResource()
    }

    private func stopAllSecurityScopedAccess() {
        for url in activeSecurityScopedURLs.values {
            url.stopAccessingSecurityScopedResource()
        }
        activeSecurityScopedURLs.removeAll()
    }

    private static func normalizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}
