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
        
        // Check for path conflicts
        try checkConflicts(plan, at: baseURL)
        
        // Validate file existence
        try validateFileExistence(plan)
        
        // Warn about large operations
        if plan.totalFiles > 1000 {
            throw ValidationError.largeOperation(plan.totalFiles)
        }
    }

    private static func validateDestinations(_ plan: OrganizationPlan, at baseURL: URL, allowedLocations: [StorageLocation]) throws {
        func checkSuggestion(_ suggestion: FolderSuggestion, depth: Int) throws {
            // Check depth limit (max 3 levels as per instructions)
            if depth > 3 {
                throw ValidationError.folderTooDeep(suggestion.folderName)
            }

            // Check if it's an absolute path
            if suggestion.folderName.hasPrefix("/") {
                let path = suggestion.folderName
                let isValidLocation = allowedLocations.contains { $0.path == path }
                
                if !isValidLocation {
                    throw ValidationError.invalidStorageLocation(path)
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
            let folderURL = parentURL.appendingPathComponent(suggestion.folderName, isDirectory: true)
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
        
        func checkFiles(_ suggestion: FolderSuggestion, destinationIsStorage: Bool) throws {
            let destIsStorage = suggestion.folderName.hasPrefix("/") && allowedLocations.contains(where: { $0.path == suggestion.folderName })
            
            for file in suggestion.files {
                guard let url = file.url else { continue }
                let filePath = url.path
                
                for location in allowedLocations {
                    if filePath.hasPrefix(location.path + "/") {
                        if !destIsStorage {
                            throw ValidationError.sourceInStorageLocation(file.displayName, location.name)
                        }
                    }
                }
            }
            
            for subfolder in suggestion.subfolders {
                try checkFiles(subfolder, destinationIsStorage: destIsStorage)
            }
        }
        
        for suggestion in plan.suggestions {
            try checkFiles(suggestion, destinationIsStorage: false)
        }
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
    
    var errorDescription: String? {
        switch self {
        case .baseDirectoryNotFound:
            return "Base directory not found"
        case .pathConflict(let path):
            return "Path conflict: \(path)"
        case .pathExists(let path):
            return "Cannot create folder: A file already exists at '\(path)'. The AI suggested a folder name that conflicts with an existing file."
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .largeOperation(let count):
            return "Large operation detected (\(count) files). Please review carefully."
        case .tooManyFolders(let count, let max):
            return "Too many top-level folders (\(count)). Maximum allowed is \(max). Consider consolidating categories."
        case .invalidStorageLocation(let path):
            return "Invalid storage location: \(path). The AI suggested a path that is not in your approved storage locations list."
        case .folderTooDeep(let folder):
            return "Folder structure is too deep at '\(folder)'. Maximum depth is 3 levels."
        case .sourceInStorageLocation(let file, let location):
            return "File '\(file)' is inside storage location '\(location)' and cannot be moved out. Files in storage locations are protected from reorganization."
        }
    }
}



