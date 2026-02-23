//
//  StorageLocation.swift
//  Sorty
//
//  Model for storage locations - directories where files can be moved TO
//  but won't be reorganized themselves. These serve as destination bins.
//

import Foundation
import Combine

/// RAII-style wrapper for security-scoped resource access
public class ScopedSecurityAccess {
    public let url: URL
    private let didAccess: Bool
    
    public init(url: URL, didAccess: Bool) {
        self.url = url
        self.didAccess = didAccess
    }
    
    deinit {
        cleanup()
    }
    
    public func cleanup() {
        if didAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
}

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
        let canonicalPath = StorageLocationPathResolver.canonicalPath(path)
        self.id = id
        self.path = canonicalPath
        self.name = name ?? URL(fileURLWithPath: canonicalPath).lastPathComponent
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
        let canonicalPath = StorageLocationPathResolver.canonicalPath(path)
        var context = "- \(name) (\(canonicalPath))"
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
        setupNotificationObservers()
    }
    
    private func setupNotificationObservers() {
        NotificationCenter.default.addMainActorObserver(forName: .clearAllUsageData, object: nil, queue: .main) { [weak self] in
            self?.clearAll()
        }
    }
    
    public var enabledLocations: [StorageLocation] {
        var deduped: [StorageLocation] = []
        var seenPaths: Set<String> = []

        for location in locations where location.isEnabled && location.exists && location.accessStatus != .lost {
            let canonicalPath = StorageLocationPathResolver.canonicalPath(location.path)
            guard seenPaths.insert(canonicalPath).inserted else { continue }

            var normalizedLocation = location
            normalizedLocation.path = canonicalPath
            deduped.append(normalizedLocation)
        }

        return deduped
    }

    public func clearAll() {
        // Stop accessing all security scoped resources
        for location in locations {
            if let bookmarkData = location.bookmarkData {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmarkData, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    url.stopAccessingSecurityScopedResource()
                }
            }
        }
        locations.removeAll()
        userDefaults.removeObject(forKey: storageKey)
    }
    
    public func addLocation(_ location: StorageLocation) {
        var normalized = location
        normalized.path = StorageLocationPathResolver.canonicalPath(location.path)

        // Avoid duplicates, even if path formatting differs (e.g. trailing slash)
        guard !locations.contains(where: { StorageLocationPathResolver.pathsEqual($0.path, normalized.path) }) else { return }
        locations.append(normalized)
        saveLocations()
    }
    
    public func addLocation(url: URL, description: String? = nil, customName: String? = nil) throws {
        // For picker URLs, explicitly starting security scope improves bookmark reliability
        // for folders outside default sandbox access (for example Downloads/Desktop/external volumes).
        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let bookmarkData = try url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        // Activate the newly created bookmark in this session so the location is immediately usable.
        var isStale = false
        if let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) {
            _ = resolvedURL.startAccessingSecurityScopedResource()
        }
        
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
        let normalizedPath = StorageLocationPathResolver.canonicalPath(location.path)
        if locations.contains(where: { $0.id != location.id && StorageLocationPathResolver.pathsEqual($0.path, normalizedPath) }) {
            return
        }

        if let index = locations.firstIndex(where: { $0.id == location.id }) {
            var normalized = location
            normalized.path = normalizedPath
            locations[index] = normalized
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
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        guard !enabled.isEmpty else { return nil }
        let validPaths = enabled.map(\.path)
        let existingSubfoldersByRoot = enabled.reduce(into: [String: [String]]()) { result, location in
            let existingSubfolders = discoverExistingSubfolders(for: location)
            if !existingSubfolders.isEmpty {
                result[location.path] = existingSubfolders
            }
        }
        
        var prompt = """
        ## STORAGE LOCATIONS (Additional Destinations)
        
        The following directories are approved destination bins.
        Route files there only when the file intent clearly matches the location purpose:
        
        """
        
        for location in enabled {
            prompt += location.promptContext + "\n"
        }

        let quotedPaths = validPaths.map { "\"\($0)\"" }.joined(separator: ", ")
        prompt += "\nVALID_STORAGE_PATHS = [\(quotedPaths)]\n"

        if !existingSubfoldersByRoot.isEmpty {
            prompt += "\nKNOWN_STORAGE_SUBFOLDERS (use these EXACT absolute paths as folder names when routing files here):\n"
            for location in enabled {
                guard let subfolders = existingSubfoldersByRoot[location.path], !subfolders.isEmpty else { continue }
                prompt += "- \(location.name):\n"
                for subfolder in subfolders {
                    prompt += "  - \(subfolder)\n"
                }
            }
        }
        
        let examplePath = validPaths.first ?? "/Users/me/Archive"
        prompt += """
        
        STORAGE LOCATION RULES:
        1. Storage destinations must use absolute paths from VALID_STORAGE_PATHS or their subfolders.
        2. ONLY use the storage roots listed above. Any absolute path outside those roots will be rejected.
        3. FIRST check KNOWN_STORAGE_SUBFOLDERS. When an existing subfolder matches the file's purpose, use its EXACT absolute path as the folder "name" in JSON.
        4. Never use relative placeholders such as "storage", "storage location", "archive", "Spreadsheets", or any other relative name as folder names when targeting storage.
        5. Match files to storage locations based on each location's stated purpose/description.
        6. Files that don't clearly fit any storage location should be organized within the source directory using relative paths.
        7. Do NOT move files that are already inside a storage location to non-storage destinations.
        8. It is perfectly fine to use zero, one, or multiple storage locations in a single plan — let the files guide your decision.
        9. Use the FULL absolute path as the folder "name" in JSON (e.g. "name": "/Users/me/Archive/Documents").
           Do NOT split the path into a nested folder hierarchy. Do NOT use PascalCase variants of folder names.
        10. Place files directly in the matching storage subfolder. Do NOT create additional sub-categories inside storage locations unless the user explicitly requests it.
        
        REQUIRED JSON FORMAT when routing files to storage:
        {"folders":[{"name":"\(examplePath)","files":[{"filename":"example.xlsx"}]}]}
        The folder "name" MUST be the absolute path copied from VALID_STORAGE_PATHS above — NOT a relative name.
        """
        
        return prompt
    }

    /// Returns known subfolders for each enabled storage location.
    /// Keys are canonical root paths; values are lists of discovered subfolder absolute paths.
    public func discoverAllSubfolders() -> [String: [String]] {
        let enabled = enabledLocations
        return enabled.reduce(into: [String: [String]]()) { result, location in
            let subfolders = discoverExistingSubfolders(
                for: location,
                maxDepth: 3,
                maxCount: 200
            )
            if !subfolders.isEmpty {
                result[location.path] = subfolders
            }
        }
    }
    
    /// Resolves a storage location URL with security-scoped access
    /// Returns a wrapper that ensures balanced access (call .cleanup() when done)
    public func resolveURL(for location: StorageLocation) -> ScopedSecurityAccess? {
        guard let bookmarkData = location.bookmarkData else {
            return ScopedSecurityAccess(url: location.url, didAccess: false)
        }
        
        var isStale = false
        do {
            let url = try URL(resolvingBookmarkData: bookmarkData,
                              options: .withSecurityScope,
                              relativeTo: nil,
                              bookmarkDataIsStale: &isStale)
            
            if url.startAccessingSecurityScopedResource() {
                return ScopedSecurityAccess(url: url, didAccess: true)
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
    
    /// Re-authorizes a storage location by creating a new security-scoped bookmark from a freshly-picked URL
    public func reauthorizeLocation(_ location: StorageLocation, with url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            DebugLogger.log("Failed to access security-scoped resource for reauthorization: \(url.path)")
            return
        }

        do {
            let newBookmarkData = try url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )

            var updated = location
            updated.bookmarkData = newBookmarkData
            updated.path = url.path
            updated.accessStatus = .valid
            updateLocation(updated)

            DebugLogger.log("Successfully reauthorized storage location: \(location.name)")
        } catch {
            url.stopAccessingSecurityScopedResource()
            DebugLogger.log("Failed to create bookmark during reauthorization: \(error)")
        }
    }

    private func discoverExistingSubfolders(
        for location: StorageLocation,
        maxDepth: Int = 3,
        maxCount: Int = 12
    ) -> [String] {
        let scopedAccess = resolveURL(for: location)
        let rootURL = scopedAccess?.url ?? location.url
        defer { scopedAccess?.cleanup() }

        var discovered: [String] = []
        let fileManager = FileManager.default

        func scan(_ directoryURL: URL, depth: Int) {
            guard depth <= maxDepth, discovered.count < maxCount else { return }

            guard let contents = try? fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                options: [.skipsHiddenFiles]
            ) else {
                return
            }

            let subdirectories = contents.compactMap { item -> URL? in
                guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
                      values.isDirectory == true,
                      values.isSymbolicLink != true else {
                    return nil
                }
                return item
            }
            .sorted { lhs, rhs in
                lhs.lastPathComponent.localizedCaseInsensitiveCompare(rhs.lastPathComponent) == .orderedAscending
            }

            for subdirectory in subdirectories {
                discovered.append(StorageLocationPathResolver.canonicalPath(subdirectory.path))
                guard discovered.count < maxCount else { break }
                scan(subdirectory, depth: depth + 1)
                guard discovered.count < maxCount else { break }
            }
        }

        scan(rootURL, depth: 1)
        return discovered
    }

    private func loadLocations() {
        if let data = userDefaults.data(forKey: storageKey),
           let decoded = try? JSONDecoder().decode([StorageLocation].self, from: data) {
            var normalized: [StorageLocation] = []
            var seenPaths: Set<String> = []

            for var location in decoded {
                location.path = StorageLocationPathResolver.canonicalPath(location.path)
                guard seenPaths.insert(location.path).inserted else { continue }
                normalized.append(location)
            }

            locations = normalized
        }
    }
    
    private func saveLocations() {
        if let encoded = try? JSONEncoder().encode(locations) {
            userDefaults.set(encoded, forKey: storageKey)
        }
    }
}
