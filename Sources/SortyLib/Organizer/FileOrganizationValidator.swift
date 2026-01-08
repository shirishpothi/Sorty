//
//  FileOrganizationValidator.swift
//  Sorty
//
//  Validates organization plan before execution
//

import Foundation

struct FileOrganizationValidator {
    static func validate(_ plan: OrganizationPlan, at baseURL: URL) throws {
        let fileManager = FileManager.default
        
        // Check if base directory exists
        guard fileManager.fileExists(atPath: baseURL.path) else {
            throw ValidationError.baseDirectoryNotFound
        }
        
        // Check for path conflicts
        try checkConflicts(plan, at: baseURL)
        
        // Validate file existence
        try validateFileExistence(plan)
        
        // Warn about large operations
        if plan.totalFiles > 1000 {
            throw ValidationError.largeOperation(plan.totalFiles)
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
            
            if fileManager.fileExists(atPath: folderPath) {
                throw ValidationError.pathExists(folderPath)
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
}

enum ValidationError: LocalizedError {
    case baseDirectoryNotFound
    case pathConflict(String)
    case pathExists(String)
    case fileNotFound(String)
    case largeOperation(Int)
    
    var errorDescription: String? {
        switch self {
        case .baseDirectoryNotFound:
            return "Base directory not found"
        case .pathConflict(let path):
            return "Path conflict: \(path)"
        case .pathExists(let path):
            return "Path already exists: \(path)"
        case .fileNotFound(let path):
            return "File not found: \(path)"
        case .largeOperation(let count):
            return "Large operation detected (\(count) files). Please review carefully."
        }
    }
}



