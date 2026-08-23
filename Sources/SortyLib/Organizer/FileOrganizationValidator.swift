//
//  FileOrganizationValidator.swift
//  Sorty
//
//  Validates organization plan before execution
//

import Foundation

struct FileOrganizationValidator {
    static func validate(
        _ plan: OrganizationPlan,
        at baseURL: URL,
        allowedStorageLocations: [StorageLocation] = [],
        mode: OrganizationMode = .organize
    ) throws {
        let fileManager = FileManager.default
        
        // Check if base directory exists
        guard fileManager.fileExists(atPath: baseURL.path) else {
            throw ValidationError.baseDirectoryNotFound
        }
        
        if mode != .renameOnly {
            // These checks protect AI-created destinations. Rename-only destinations
            // are derived from existing source folders by OrganizationModePlanEnforcer.
            try validateDestinations(plan, at: baseURL, allowedLocations: allowedStorageLocations)
            try checkConflicts(plan, at: baseURL)
        }
        
        // Validate file existence
        try validateFileExistence(plan)
        
        // Large operations are allowed. We keep validation focused on correctness
        // constraints (conflicts, missing files, and storage safety).
    }

    private static func validateDestinations(_ plan: OrganizationPlan, at baseURL: URL, allowedLocations: [StorageLocation]) throws {
        let allowedPaths = Set(allowedLocations.map { StorageLocationPathResolver.resolvedPath($0.path) })

        func checkSuggestion(_ suggestion: FolderSuggestion) throws {
            // Check if this destination is an absolute storage location
            if let absolutePath = StorageLocationPathResolver.normalizedAbsolutePath(from: suggestion.folderName) {
                let resolvedPath = StorageLocationPathResolver.resolvedPath(absolutePath)
                if !isAllowedStorageDestination(resolvedPath, allowedRoots: allowedPaths) {
                    throw ValidationError.invalidStorageLocation(absolutePath)
                }
            }

            // Check subfolders
            for subfolder in suggestion.subfolders {
                try checkSuggestion(subfolder)
            }
        }

        for suggestion in plan.suggestions {
            try checkSuggestion(suggestion)
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
    case invalidStorageLocation(String)
    
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
        case .invalidStorageLocation(let path):
            return "Invalid storage location: \(path). Sorty suggested a path that is not in your approved storage locations list."
        }
    }
}
