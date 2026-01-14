//
//  StorageLocation.swift
//  Sorty
//
//  Model for storage locations - directories where files can be moved TO
//  but won't be reorganized themselves. These serve as destination bins.
//

import Foundation
import Combine

/// A storage location that can receive files during organization
/// These directories are NOT organized - they serve as destination bins
public struct StorageLocation: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public var path: String
    public var name: String
    public var description: String? // User-provided description for AI context (e.g., "Archive for old projects")
    public var isEnabled: Bool
    public var bookmarkData: Data?
    public var accessStatus: FolderAccessStatus = .unknown
    
    public init(
        id: UUID = UUID(),
        path: String,
        name: String? = nil,
        description: String? = nil,
        isEnabled: Bool = true,
        bookmarkData: Data? = nil
    ) {
        self.id = id
        self.path = path
        self.name = name ?? URL(fileURLWithPath: path).lastPathComponent
        self.description = description
        self.isEnabled = isEnabled
        self.bookmarkData = bookmarkData
    }
    
    public var url: URL {
        URL(fileURLWithPath: path)
    }
    
    public var exists: Bool {
        FileManager.default.fileExists(atPath: path)
    }
    
    /// Returns the prompt context for AI to understand this storage location
    public var promptContext: String {
        var context = "- \(name) (\(path))"
        if let desc = description, !desc.isEmpty {
            context += ": \(desc)"
        }
        return context
    }
}

/// Manager for persisting storage locations
@MainActor
public class StorageLocationsManager: ObservableObject {
    @Published public private(set) var locations: [StorageLocation] = []
    private let userDefaults = UserDefaults.standard
    private let storageKey = "storageLocations"
    
    public init() {
        loadLocations()
    }
    
    public var enabledLocations: [StorageLocation] {
        locations.filter { $0.isEnabled && $0.exists }
    }
    
    public func addLocation(_ location: StorageLocation) {
        // Avoid duplicates
        guard !locations.contains(where: { $0.path == location.path }) else { return }
        locations.append(location)
        saveLocations()
    }
    
    public func addLocation(url: URL, description: String? = nil, customName: String? = nil) throws {
        // Create security-scoped bookmark
        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        
        let location = StorageLocation(
            path: url.path,
            name: customName ?? url.lastPathComponent,
            description: description,
            isEnabled: true,
            bookmarkData: bookmarkData
        )
        
        addLocation(location)
    }
    
    public func removeLocation(_ location: StorageLocation) {
        // Stop accessing security scoped resource before removing
        if let bookmarkData = location.bookmarkData {
            var isStale = false
            if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                url.stopAccessingSecurityScopedResource()
            }
        }
        locations.removeAll { $0.id == location.id }
        saveLocations()
    }
    
    public func updateLocation(_ location: StorageLocation) {
        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            locations[index] = location
            saveLocations()
        }
    }
    
    public func toggleEnabled(for location: StorageLocation) {
        if var updated = locations.first(where: { $0.id == location.id }) {
            updated.isEnabled.toggle()
            updateLocation(updated)
        }
    }
    
    /// Generates prompt context for all enabled storage locations
    public func generatePromptContext() -> String? {
        let enabled = enabledLocations
        guard !enabled.isEmpty else { return nil }
        
        var prompt = """
        STORAGE LOCATIONS:
        The following directories are available as additional destinations for files.
        You may move files TO these locations if appropriate, but do NOT reorganize files already in them.
        These are external storage bins - use them for files that don't belong in the main directory:
        
        """
        
        for location in enabled {
            prompt += location.promptContext + "\n"
        }
        
        prompt += """
        
        When suggesting moves to storage locations, use the FULL PATH as the destination.
        Only use storage locations when files clearly belong there based on the location's purpose.
        """
        
        return prompt
    }
    
    /// Resolves a storage location URL with security-scoped access
    public func resolveURL(for location: StorageLocation) -> URL? {
        guard let bookmarkData = location.bookmarkData else {
            return location.url
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                return url
            }
        } catch {
            DebugLogger.log("Failed to resolve storage location bookmark: \(error)")
        }
        
        return nil
    }
    
    /// Restores access to all security-scoped bookmarks
    public func restoreSecurityScopedAccess() {
        var updatedLocations = locations
        var hasChanges = false
        
        for (index, location) in locations.enumerated() {
            guard let bookmarkData = location.bookmarkData else {
                continue
            }
            
            var isStale = false
            do {
                let url = try URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale)
                
                if url.startAccessingSecurityScopedResource() {
                    if isStale {
                        // Recreate bookmark
                        if let newData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) {
                            updatedLocations[index].bookmarkData = newData
                            hasChanges = true
                        }
                        updatedLocations[index].accessStatus = .stale
                    } else {
                        updatedLocations[index].accessStatus = .valid
                    }
                    
                    // Update path if it changed
                    if url.path != location.path {
                        updatedLocations[index].path = url.path
                        hasChanges = true
                    }
                } else {
                    updatedLocations[index].accessStatus = .lost
                    hasChanges = true
                }
            } catch {
                DebugLogger.log("Failed to resolve storage location bookmark: \(error)")
                updatedLocations[index].accessStatus = .lost
                hasChanges = true
            }
        }
        
        if hasChanges {
            locations = updatedLocations
            saveLocations()
        }
    }
    
    private func loadLocations() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StorageLocation].self, from: data) {
            locations = decoded
        }
    }
    
    private func saveLocations() {
        if let encoded = try? JSONEncoder().encode(locations) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
