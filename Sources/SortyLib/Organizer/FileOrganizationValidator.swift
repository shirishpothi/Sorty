//
//  FileOrganizationValidator.swift
//  Sorty
//
//  Validates organization plan before execution
//

import Foundation

struct FileOrganizationValidator {
    static func validate(_ plan: OrganizationPlan, at baseURL: URL, allowedStorageLocations: [StorageLocation] = [], maxTopLevelFolders: Int = 10) throws {
        let fileManager = FileManager.default
        
        // Check if base directory exists
        guard fileManager.fileExists(atPath: baseURL.path) else {
            throw ValidationError.baseDirectoryNotFound
        }
        
        // Check folder count limit
        if plan.suggestions.count > maxTopLevelFolders {
            throw ValidationError.tooManyFolders(plan.suggestions.count, max: maxTopLevelFolders)
        }
        
        // Check for storage location and depth validity
        try validateDestinations(plan, at: baseURL, allowedLocations: allowedStorageLocations)
        
        // Check that files in storage locations aren't moved out
        try validateSourcePaths(plan, allowedLocations: allowedStorageLocations)

        // Keep storage usage conservative by default
        try validateStorageUsage(plan, at: baseURL, allowedLocations: allowedStorageLocations)
        
        // Check for path conflicts
        try checkConflicts(plan, at: baseURL)
        
        // Validate file existence
        try validateFileExistence(plan)
        
        // Large operations are allowed. We keep validation focused on correctness
        // constraints (conflicts, missing files, storage safety, folder limits).
    }

    private static func validateDestinations(_ plan: OrganizationPlan, at baseURL: URL, allowedLocations: [StorageLocation]) throws {
        let allowedPaths = Set(allowedLocations.map { StorageLocationPathResolver.canonicalPath($0.path) })

        func checkSuggestion(_ suggestion: FolderSuggestion, depth: Int) throws {
            // Check depth limit (max 3 levels as per instructions)
            if depth > 3 {
                throw ValidationError.folderTooDeep(suggestion.folderName)
            }

            // Check if this destination is an absolute storage location
            if let absolutePath = StorageLocationPathResolver.normalizedAbsolutePath(from: suggestion.folderName) {
                if !isAllowedStorageDestination(absolutePath, allowedRoots: allowedPaths) {
                    throw ValidationError.invalidStorageLocation(absolutePath)
                }
            }

            // Check subfolders
            for subfolder in suggestion.subfolders {
                try checkSuggestion(subfolder, depth: depth + 1)
            }
        }

        for suggestion in plan.suggestions {
            try checkSuggestion(suggestion, depth: 1)
        }
    }
    
    static func checkConflicts(_ plan: OrganizationPlan, at baseURL: URL) throws {
        var existingPaths: Set<String> = []
        let fileManager = FileManager.default
        
        func checkSuggestion(_ suggestion: FolderSuggestion, parentURL: URL) throws {
            let folderURL: URL
            if let absoluteURL = StorageLocationPathResolver.absoluteURL(from: suggestion.folderName) {
                folderURL = absoluteURL
            } else {
                folderURL = parentURL.appendingPathComponent(suggestion.folderName, isDirectory: true)
            }
            let folderPath = folderURL.path
            
            if existingPaths.contains(folderPath) {
                throw ValidationError.pathConflict(folderPath)
            }
            
            // Allow organizing into existing directories - only reject paths that exist as files
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: folderPath, isDirectory: &isDirectory) {
                if !isDirectory.boolValue {
                    // Path exists but is a file, not a directory - this is a conflict
                    throw ValidationError.pathExists(folderPath)
                }
                // If it's already a directory, that's fine - we can organize into it
            }
            
            existingPaths.insert(folderPath)
            
            // Check subfolders
            for subfolder in suggestion.subfolders {
                try checkSuggestion(subfolder, parentURL: folderURL)
            }
        }
        
        for suggestion in plan.suggestions {
            try checkSuggestion(suggestion, parentURL: baseURL)
        }
    }
    
    static func validateFileExistence(_ plan: OrganizationPlan) throws {
        let fileManager = FileManager.default
        
        func validateFiles(_ suggestion: FolderSuggestion) throws {
            for file in suggestion.files {
                guard let url = file.url else {
                    throw ValidationError.fileNotFound(file.path)
                }
                
                if !fileManager.fileExists(atPath: url.path) {
                    throw ValidationError.fileNotFound(file.path)
                }
            }
            
            for subfolder in suggestion.subfolders {
                try validateFiles(subfolder)
            }
        }
        
        for suggestion in plan.suggestions {
            try validateFiles(suggestion)
        }
        
        for file in plan.unorganizedFiles {
            guard let url = file.url else {
                throw ValidationError.fileNotFound(file.path)
            }
            
            if !fileManager.fileExists(atPath: url.path) {
                throw ValidationError.fileNotFound(file.path)
            }
        }
    }
    
    private static func validateSourcePaths(_ plan: OrganizationPlan, allowedLocations: [StorageLocation]) throws {
        guard !allowedLocations.isEmpty else { return }

        let allowedPathSet = Set(allowedLocations.map { StorageLocationPathResolver.canonicalPath($0.path) })
        let normalizedLocations: [(location: StorageLocation, normalizedPath: String)] = allowedLocations.compactMap { location in
            let normalized = StorageLocationPathResolver.canonicalPath(location.path)
            guard allowedPathSet.contains(normalized) else { return nil }
            return (location, normalized)
        }
        
        func checkFiles(_ suggestion: FolderSuggestion, destinationIsStorage: Bool) throws {
            let destinationPath = StorageLocationPathResolver.normalizedAbsolutePath(from: suggestion.folderName)
            let destinationMatchesStorage = destinationPath.map { isAllowedStorageDestination($0, allowedRoots: allowedPathSet) } ?? false
            let effectiveDestinationIsStorage = destinationIsStorage || destinationMatchesStorage
            
            for file in suggestion.files {
                guard let url = file.url else { continue }
                let filePath = StorageLocationPathResolver.canonicalPath(url.path)
                
                for (location, locationPath) in normalizedLocations {
                    if StorageLocationPathResolver.isPath(filePath, within: locationPath), !effectiveDestinationIsStorage {
                        throw ValidationError.sourceInStorageLocation(file.displayName, location.name)
                    }
                }
            }
            
            for subfolder in suggestion.subfolders {
                try checkFiles(subfolder, destinationIsStorage: effectiveDestinationIsStorage)
            }
        }
        
        for suggestion in plan.suggestions {
            try checkFiles(suggestion, destinationIsStorage: false)
        }
    }

    private static func validateStorageUsage(_ plan: OrganizationPlan, at baseURL: URL, allowedLocations: [StorageLocation]) throws {
        guard !allowedLocations.isEmpty else { return }

        let allowedPathSet = Set(allowedLocations.map { StorageLocationPathResolver.canonicalPath($0.path) })
        let canonicalBasePath = StorageLocationPathResolver.canonicalPath(baseURL.path)
        var totalFilesBySourceParent: [String: Int] = [:]
        var storageFilesBySourceParent: [String: Int] = [:]

        func isInStorageRoot(_ path: String) -> Bool {
            allowedPathSet.contains { StorageLocationPathResolver.isPath(path, within: $0) }
        }

        func sourceParentPath(for file: FileItem) -> String? {
            guard let fileURL = file.url else { return nil }
            let sourcePath = StorageLocationPathResolver.canonicalPath(fileURL.path)
            let parent = URL(fileURLWithPath: sourcePath, isDirectory: file.isDirectory)
                .deletingLastPathComponent()
                .path
            let canonicalParent = StorageLocationPathResolver.canonicalPath(parent)
            return canonicalParent.isEmpty ? nil : canonicalParent
        }

        func registerTotal(_ file: FileItem) {
            guard let parentPath = sourceParentPath(for: file), !isInStorageRoot(parentPath) else { return }
            totalFilesBySourceParent[parentPath, default: 0] += 1
        }

        func checkSuggestion(_ suggestion: FolderSuggestion, destinationIsStorage: Bool) throws {
            let destinationPath = StorageLocationPathResolver.normalizedAbsolutePath(from: suggestion.folderName)
            let destinationMatchesStorage = destinationPath.map { isAllowedStorageDestination($0, allowedRoots: allowedPathSet) } ?? false
            let effectiveDestinationIsStorage = destinationIsStorage || destinationMatchesStorage

            for file in suggestion.files {
                registerTotal(file)

                guard effectiveDestinationIsStorage,
                      let parentPath = sourceParentPath(for: file),
                      !isInStorageRoot(parentPath) else {
                    continue
                }

                if file.isDirectory {
                    throw ValidationError.directoryMovedToStorage(file.displayName)
                }
                storageFilesBySourceParent[parentPath, default: 0] += 1
            }

            for subfolder in suggestion.subfolders {
                try checkSuggestion(subfolder, destinationIsStorage: effectiveDestinationIsStorage)
            }
        }

        for suggestion in plan.suggestions {
            try checkSuggestion(suggestion, destinationIsStorage: false)
        }

        for file in plan.unorganizedFiles {
            registerTotal(file)
        }

        for (sourceParent, totalCount) in totalFilesBySourceParent {
            guard sourceParent != canonicalBasePath else { continue }
            let movedToStorageCount = storageFilesBySourceParent[sourceParent] ?? 0

            // Treat moving every file from a non-root source subfolder to storage as folder-level routing.
            if totalCount >= 3, movedToStorageCount == totalCount {
                let folderName = URL(fileURLWithPath: sourceParent).lastPathComponent
                throw ValidationError.folderBulkMovedToStorage(folderName, totalCount)
            }
        }
    }

    private static func isAllowedStorageDestination(_ absolutePath: String, allowedRoots: Set<String>) -> Bool {
        for rootPath in allowedRoots where StorageLocationPathResolver.isPath(absolutePath, within: rootPath) {
            return true
        }
        return false
    }
}

enum ValidationError: LocalizedError {
    case baseDirectoryNotFound
    case pathConflict(String)
    case pathExists(String)
    case fileNotFound(String)
    case largeOperation(Int)
    case tooManyFolders(Int, max: Int)
    case invalidStorageLocation(String)
    case folderTooDeep(String)
    case sourceInStorageLocation(String, String)
    case directoryMovedToStorage(String)
    case folderBulkMovedToStorage(String, Int)
    
    var errorDescription: String? {
        switch self {
        case .baseDirectoryNotFound:
            return "Base directory not found"
        case .pathConflict(let path):
            return "Path conflict: \(path)"
        case .pathExists(let path):
            return "Cannot create folder: A file already exists at '\(path)'. Sorty suggested a folder name that conflicts with an existing file."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .largeOperation(let count):
            return "Large operation detected (\(count) files). Please review carefully."
        case .tooManyFolders(let count, let max):
            return "Too many top-level folders (\(count)). Maximum allowed is \(max). Consider consolidating categories."
        case .invalidStorageLocation(let path):
            return "Invalid storage location: \(path). Sorty suggested a path that is not in your approved storage locations list."
        case .folderTooDeep(let folder):
            return "Folder structure is too deep at '\(folder)'. Maximum depth is 3 levels."
        case .sourceInStorageLocation(let file, let location):
            return "File '\(file)' is inside storage location '\(location)' and cannot be moved out. Files in storage locations are protected from reorganization."
        case .directoryMovedToStorage(let itemName):
            return "Directory '\(itemName)' cannot be moved to a storage location automatically. Route individual files to storage instead."
        case .folderBulkMovedToStorage(let folderName, let count):
            return "Refusing to move all \(count) files from '\(folderName)' to storage. Storage locations are for specific files, not whole folders, unless explicitly requested."
        }
    }
}
