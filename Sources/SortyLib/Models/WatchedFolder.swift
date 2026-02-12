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
    private let userDefaults = UserDefaults.standard
    private let storageKey = "watchedFolders"
    
    public init() {
        loadFolders()
    }
    
    public func addFolder(_ folder: WatchedFolder) {
        // Avoid duplicates
        guard !folders.contains(where: { $0.path == folder.path }) else { return }
        folders.append(folder)
        saveFolders()
    }
    
    public func removeFolder(_ folder: WatchedFolder) {
        // Stop accessing security scoped resource before removing
        if let bookmarkData = folder.bookmarkData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                url.stopAccessingSecurityScopedResource()
            }
        }
        folders.removeAll { $0.id == folder.id }
        saveFolders()
    }
    
    public func updateFolder(_ folder: WatchedFolder) {
        if let index = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[index] = folder
            saveFolders()
        }
    }
    
    public func toggleEnabled(for folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.isEnabled.toggle()
            updateFolder(updated)
        }
    }
    
    public func toggleAutoOrganize(for folder: WatchedFolder) {
        if var updated = folders.first(where: { $0.id == folder.id }) {
            updated.autoOrganize.toggle()
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
            if folder.autoOrganize {
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
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
                
                if url.startAccessingSecurityScopedResource() {
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
                _ = resolvedURL.startAccessingSecurityScopedResource()
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
            folders = decoded
        }
    }
    
    private func saveFolders() {
        if let encoded = try? JSONEncoder().encode(folders) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
