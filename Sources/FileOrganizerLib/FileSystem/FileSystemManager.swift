//
//  FileSystemManager.swift
//  FileOrganizer
//
//  Safe file operations with undo tracking, conflict handling, and improved revert support
//  Fixed: History revert now properly handles all operations and prevents re-organization
//

import Foundation
import Combine

public actor FileSystemManager {
    private var undoStack: [FileOperation] = []
    private let fileManager = FileManager.default

    // Track files that are currently being reverted to prevent re-organization
    private var revertingPaths: Set<String> = []

    public struct FileOperation: Codable, Hashable, Sendable {
        public let id: UUID
        public let type: OperationType
        public let sourcePath: String
        public let destinationPath: String?
        public let timestamp: Date
        public let metadata: OperationMetadata?

        public enum OperationType: String, Codable, Sendable {
            case createFolder
            case moveFile
            case renameFile
            case deleteFile
            case copyFile
            case tagFile
        }

        public struct OperationMetadata: Codable, Hashable, Sendable {
            public var originalFilename: String?
            public var newFilename: String?
            public var wasCreatedDuringOrganization: Bool
            public var parentFolderPath: String?
            public var originalTags: [String]?
            public var newTags: [String]?

            public init(
                originalFilename: String? = nil,
                newFilename: String? = nil,
                wasCreatedDuringOrganization: Bool = false,
                parentFolderPath: String? = nil,
                originalTags: [String]? = nil,
                newTags: [String]? = nil
            ) {
                self.originalFilename = originalFilename
                self.newFilename = newFilename
                self.wasCreatedDuringOrganization = wasCreatedDuringOrganization
                self.parentFolderPath = parentFolderPath
                self.originalTags = originalTags
                self.newTags = newTags
            }
        }

        public init(
            id: UUID = UUID(),
            type: OperationType,
            sourcePath: String,
            destinationPath: String?,
            timestamp: Date = Date(),
            metadata: OperationMetadata? = nil
        ) {
            self.id = id
            self.type = type
            self.sourcePath = sourcePath
            self.destinationPath = destinationPath
            self.timestamp = timestamp
            self.metadata = metadata
        }
    }

    public init() {}

    // MARK: - Revert Protection

    /// Check if a path is currently being reverted
    public func isPathBeingReverted(_ path: String) -> Bool {
        return revertingPaths.contains(path) || revertingPaths.contains { path.hasPrefix($0) }
    }

    /// Mark paths as being reverted to prevent re-organization
    private func markPathsAsReverting(_ paths: [String]) {
        for path in paths {
            revertingPaths.insert(path)
        }
    }

    /// Clear revert marks after completion
    private func clearRevertMarks(_ paths: [String]) {
        for path in paths {
            revertingPaths.remove(path)
        }
    }

    // MARK: - Folder Creation

    func createFolders(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false) async throws -> [FileOperation] {
        var operations: [FileOperation] = []

        func createFolderRecursive(_ suggestion: FolderSuggestion, parentURL: URL) throws {
            let folderURL = parentURL.appendingPathComponent(suggestion.folderName, isDirectory: true)

            if !dryRun {
                var isDirectory: ObjCBool = false
                if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) {
                    if isDirectory.boolValue {
                        // Folder already exists, continue with subfolders
                    } else {
                        // Conflict: File exists where folder should be
                        let backupURL = folderURL.deletingLastPathComponent()
                            .appendingPathComponent("\(suggestion.folderName)_file_backup_\(UUID().uuidString.prefix(8))")
                        try fileManager.moveItem(at: folderURL, to: backupURL)

                        // Record this move for undo
                        operations.append(FileOperation(
                            id: UUID(),
                            type: .moveFile,
                            sourcePath: folderURL.path,
                            destinationPath: backupURL.path,
                            timestamp: Date(),
                            metadata: FileOperation.OperationMetadata(wasCreatedDuringOrganization: true)
                        ))

                        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)

                        operations.append(FileOperation(
                            id: UUID(),
                            type: .createFolder,
                            sourcePath: folderURL.path,
                            destinationPath: nil,
                            timestamp: Date(),
                            metadata: FileOperation.OperationMetadata(wasCreatedDuringOrganization: true)
                        ))
                    }
                } else {
                    try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    operations.append(FileOperation(
                        id: UUID(),
                        type: .createFolder,
                        sourcePath: folderURL.path,
                        destinationPath: nil,
                        timestamp: Date(),
                        metadata: FileOperation.OperationMetadata(wasCreatedDuringOrganization: true)
                    ))
                }
            }

            // Create subfolders
            for subfolder in suggestion.subfolders {
                try createFolderRecursive(subfolder, parentURL: folderURL)
            }
        }

        for suggestion in plan.suggestions {
            try createFolderRecursive(suggestion, parentURL: baseURL)
        }

        return operations
    }

    // MARK: - File Moving with Rename Support

    func moveFiles(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false) async throws -> [FileOperation] {
        var operations: [FileOperation] = []

        func moveFilesInSuggestion(_ suggestion: FolderSuggestion, parentURL: URL) throws {
            let folderURL = parentURL.appendingPathComponent(suggestion.folderName, isDirectory: true)

            // Process files with potential renaming
            for file in suggestion.files {
                guard let sourceURL = file.url else { continue }

                // Check for rename mapping
                let finalFilename: String
                var renameMetadata: FileOperation.OperationMetadata? = nil

                if let mapping = suggestion.renameMapping(for: file), mapping.hasRename, let newName = mapping.suggestedName {
                    finalFilename = newName
                    renameMetadata = FileOperation.OperationMetadata(
                        originalFilename: sourceURL.lastPathComponent,
                        newFilename: newName,
                        wasCreatedDuringOrganization: false,
                        parentFolderPath: folderURL.path
                    )
                } else {
                    finalFilename = sourceURL.lastPathComponent
                }

                var destinationURL = folderURL.appendingPathComponent(finalFilename)

                // Skip if source and destination are identical
                if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
                    continue
                }

                if !dryRun {
                    // Create destination directory if needed
                    if !fileManager.fileExists(atPath: folderURL.path) {
                        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    }

                    // Handle conflicts
                    if fileManager.fileExists(atPath: destinationURL.path) {
                        destinationURL = generateUniqueURL(for: destinationURL)
                    }

                    // Verify source exists
                    guard fileManager.fileExists(atPath: sourceURL.path) else {
                        continue
                    }

                    // Move file
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }

                // Record the operation
                let operationType: FileOperation.OperationType = renameMetadata != nil ? .renameFile : .moveFile

                operations.append(FileOperation(
                    id: UUID(),
                    type: operationType,
                    sourcePath: sourceURL.path,
                    destinationPath: destinationURL.path,
                    timestamp: Date(),
                    metadata: renameMetadata
                ))
            }

            // Process subfolders
            for subfolder in suggestion.subfolders {
                try moveFilesInSuggestion(subfolder, parentURL: folderURL)
            }
        }

        for suggestion in plan.suggestions {
            try moveFilesInSuggestion(suggestion, parentURL: baseURL)
        }

        return operations
    }

    // MARK: - File Tagging

    func tagFiles(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false) async throws -> [FileOperation] {
        // Tagging is now gated by the caller using this method
        var operations: [FileOperation] = []

        func tagFilesInSuggestion(_ suggestion: FolderSuggestion, parentURL: URL) throws {
            let folderURL = parentURL.appendingPathComponent(suggestion.folderName)

            // Look for tag mappings in this suggestion
            for mapping in suggestion.fileTagMappings {
                // Find the file name (use the new name if it was renamed)
                let finalFilename = suggestion.filesWithFinalNames.first(where: { $0.file.id == mapping.originalFile.id })?.finalName ?? mapping.originalFile.displayName
                
                let fileURL = folderURL.appendingPathComponent(finalFilename)
                
                // Only proceed if we have tags to apply
                guard !mapping.tags.isEmpty else { continue }
                
                if !dryRun {
                    // Check if file exists at the expected location
                    guard fileManager.fileExists(atPath: fileURL.path) else {
                        continue
                    }
                    
                    // Get current tags for undo
                    let resourceValues = try? fileURL.resourceValues(forKeys: [.tagNamesKey])
                    let originalTags = resourceValues?.tagNames ?? []
                    
                    var newTagsSet = Set(originalTags)
                    for tag in mapping.tags {
                        newTagsSet.insert(tag)
                    }
                    let finalTags = Array(newTagsSet)
                    
                    // Apply using NSURL to avoid version check error
                    let nsURL = fileURL as NSURL
                    try? nsURL.setResourceValue(finalTags, forKey: .tagNamesKey)
                    
                    operations.append(FileOperation(
                        id: UUID(),
                        type: .tagFile,
                        sourcePath: fileURL.path,
                        destinationPath: nil,
                        timestamp: Date(),
                        metadata: FileOperation.OperationMetadata(
                            originalTags: originalTags,
                            newTags: finalTags
                        )
                    ))
                } else {
                     operations.append(FileOperation(
                        id: UUID(),
                        type: .tagFile,
                        sourcePath: fileURL.path,
                        destinationPath: nil,
                        timestamp: Date(),
                        metadata: FileOperation.OperationMetadata(
                            newTags: mapping.tags
                        )
                    ))
                }
            }

            // Recurse
            for subfolder in suggestion.subfolders {
                try tagFilesInSuggestion(subfolder, parentURL: folderURL)
            }
        }

        for suggestion in plan.suggestions {
            try tagFilesInSuggestion(suggestion, parentURL: baseURL)
        }

        return operations
    }

    // MARK: - Apply Organization

    func applyOrganization(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false, enableTagging: Bool = true) async throws -> [FileOperation] {
        var allOperations: [FileOperation] = []

        // First create all folders
        let folderOps = try await createFolders(plan, at: baseURL, dryRun: dryRun)
        allOperations.append(contentsOf: folderOps)

        // Then move all files
        let fileOps = try await moveFiles(plan, at: baseURL, dryRun: dryRun)
        allOperations.append(contentsOf: fileOps)

        // Then apply tags if enabled
        if enableTagging {
            let tagOps = try await tagFiles(plan, at: baseURL, dryRun: dryRun)
            allOperations.append(contentsOf: tagOps)
        }

        if !dryRun {
            undoStack.append(contentsOf: allOperations)

            // Cleanup: Try to remove empty source folders to "replace" the old structure
            // We collect all source paths from move operations
            let sourceFolders = Set(fileOps.compactMap { op -> String? in
                guard op.type == .moveFile || op.type == .renameFile else { return nil }
                return URL(fileURLWithPath: op.sourcePath).deletingLastPathComponent().path
            })

            // Sort by depth (deepest first) to allow recursive cleanup
            let sortedFolders = sourceFolders.sorted {
                $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count
            }

            for folderPath in sortedFolders {
                // Ensure we don't delete the base URL itself
                if folderPath != baseURL.path && folderPath.hasPrefix(baseURL.path) {
                    try? removeEmptyFolder(at: folderPath)
                }
            }
        }

        return allOperations
    }

    // MARK: - Reverse Operations (Undo/Revert)

    /// Reverses a set of operations - FIXED version with proper handling
    func reverseOperations(_ operations: [FileOperation]) async throws {
        // Collect all paths involved
        var involvedPaths: [String] = []
        for op in operations {
            involvedPaths.append(op.sourcePath)
            if let dest = op.destinationPath {
                involvedPaths.append(dest)
            }
        }

        // Mark paths as reverting to prevent re-organization by watched folders
        markPathsAsReverting(involvedPaths)

        defer {
            // Always clear revert marks when done
            clearRevertMarks(involvedPaths)
        }

        // Reverse in opposite order of creation
        let reversedOps = operations.reversed()

        // Track folders that may need cleanup
        var foldersToCleanup: Set<String> = []

        // First pass: move files back
        for operation in reversedOps {
            switch operation.type {
            case .moveFile, .renameFile:
                if let destinationPath = operation.destinationPath {
                    // Check if the moved file still exists at destination
                    if fileManager.fileExists(atPath: destinationPath) {
                        // Ensure the original directory exists
                        let originalDir = URL(fileURLWithPath: operation.sourcePath).deletingLastPathComponent()
                        if !fileManager.fileExists(atPath: originalDir.path) {
                            try fileManager.createDirectory(at: originalDir, withIntermediateDirectories: true)
                        }

                        // Determine final source path (handle conflicts)
                        var finalSourcePath = operation.sourcePath
                        if fileManager.fileExists(atPath: finalSourcePath) {
                            // Original location is occupied by something else
                            let uniqueURL = generateUniqueURL(for: URL(fileURLWithPath: finalSourcePath))
                            finalSourcePath = uniqueURL.path
                        }

                        // Move file back
                        try fileManager.moveItem(atPath: destinationPath, toPath: finalSourcePath)

                        // Mark parent folder for potential cleanup
                        let parentFolder = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
                        foldersToCleanup.insert(parentFolder)
                    }
                }

            case .createFolder:
                // Mark for cleanup (will be handled in second pass)
                foldersToCleanup.insert(operation.sourcePath)

            case .deleteFile:
                // Cannot undo deletion without backup - log warning
                DebugLogger.log("Cannot undo deletion: \(operation.sourcePath)")

            case .copyFile:
                // Remove the copy if it exists
                if let destinationPath = operation.destinationPath,
                   fileManager.fileExists(atPath: destinationPath) {
                    try fileManager.removeItem(atPath: destinationPath)
                }
                
            case .tagFile:
                // Restore original tags
                if let originalTags = operation.metadata?.originalTags {
                   let url = URL(fileURLWithPath: operation.sourcePath)
                   if fileManager.fileExists(atPath: url.path) {
                       let nsURL = url as NSURL
                       try? nsURL.setResourceValue(originalTags, forKey: .tagNamesKey)
                   }
                }
            }
        }

        // Second pass: cleanup empty folders (sorted by depth, deepest first)
        let sortedFolders = foldersToCleanup.sorted { path1, path2 in
            path1.components(separatedBy: "/").count > path2.components(separatedBy: "/").count
        }

        for folderPath in sortedFolders {
            try? removeEmptyFolder(at: folderPath)
        }
    }

    /// Remove a folder only if it's empty (including cleaning up parent folders)
    private func removeEmptyFolder(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)

            // Filter out hidden files like .DS_Store
            let significantContents = contents.filter { !$0.hasPrefix(".") }

            if significantContents.isEmpty {
                // Remove any hidden files first
                for item in contents {
                    let itemPath = (path as NSString).appendingPathComponent(item)
                    try? fileManager.removeItem(atPath: itemPath)
                }

                // Remove the folder
                try fileManager.removeItem(atPath: path)

                // Try to clean up parent folder too
                let parentPath = (path as NSString).deletingLastPathComponent
                try? removeEmptyFolder(at: parentPath)
            }
        } catch {
            // Folder might not be empty or we don't have permission
            DebugLogger.log("Could not remove folder: \(path) - \(error.localizedDescription)")
        }
    }

    // MARK: - Helpers

    /// Generate a unique filename by appending a counter
    private func generateUniqueURL(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var counter = 1
        var newURL = url

        while fileManager.fileExists(atPath: newURL.path) {
            let newName = ext.isEmpty ? "\(filename)_\(counter)" : "\(filename)_\(counter).\(ext)"
            newURL = directory.appendingPathComponent(newName)
            counter += 1
        }

        return newURL
    }

    func undoLastOperation() async throws {
        guard let lastOperation = undoStack.last else {
            throw FileSystemError.noOperationToUndo
        }

        try await reverseOperations([lastOperation])
        undoStack.removeLast()
    }

    func clearUndoStack() {
        undoStack.removeAll()
    }

    // MARK: - Utility Methods

    /// Check if a file exists at path
    func fileExists(at path: String) -> Bool {
        return fileManager.fileExists(atPath: path)
    }

    /// Get contents of a directory
    func contentsOfDirectory(at path: String) throws -> [String] {
        return try fileManager.contentsOfDirectory(atPath: path)
    }

    /// Move a single file
    func moveFile(from source: URL, to destination: URL) throws -> FileOperation {
        // Ensure destination directory exists
        let destDir = destination.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: destDir.path) {
            try fileManager.createDirectory(at: destDir, withIntermediateDirectories: true)
        }

        // Handle conflicts
        var finalDestination = destination
        if fileManager.fileExists(atPath: destination.path) {
            finalDestination = generateUniqueURL(for: destination)
        }

        try fileManager.moveItem(at: source, to: finalDestination)

        let operation = FileOperation(
            id: UUID(),
            type: .moveFile,
            sourcePath: source.path,
            destinationPath: finalDestination.path,
            timestamp: Date()
        )

        undoStack.append(operation)
        return operation
    }

    /// Rename a file
    func renameFile(at url: URL, to newName: String) throws -> FileOperation {
        let newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        if fileManager.fileExists(atPath: newURL.path) {
            throw FileSystemError.pathAlreadyExists(newURL.path)
        }

        try fileManager.moveItem(at: url, to: newURL)

        let operation = FileOperation(
            id: UUID(),
            type: .renameFile,
            sourcePath: url.path,
            destinationPath: newURL.path,
            timestamp: Date(),
            metadata: FileOperation.OperationMetadata(
                originalFilename: url.lastPathComponent,
                newFilename: newName
            )
        )

        undoStack.append(operation)
        return operation
    }

    /// Delete a file (use with caution - not easily reversible)
    func deleteFile(at url: URL, moveToTrash: Bool = true) throws -> FileOperation {
        if moveToTrash {
            var trashedURL: NSURL?
            try fileManager.trashItem(at: url, resultingItemURL: &trashedURL)

            return FileOperation(
                id: UUID(),
                type: .deleteFile,
                sourcePath: url.path,
                destinationPath: trashedURL?.path,
                timestamp: Date()
            )
        } else {
            try fileManager.removeItem(at: url)

            return FileOperation(
                id: UUID(),
                type: .deleteFile,
                sourcePath: url.path,
                destinationPath: nil,
                timestamp: Date()
            )
        }
    }
}

// MARK: - Errors

enum FileSystemError: LocalizedError {
    case noOperationToUndo
    case fileNotFound
    case permissionDenied
    case invalidPath
    case pathAlreadyExists(String)
    case revertInProgress

    var errorDescription: String? {
        switch self {
        case .noOperationToUndo:
            return "No operation to undo"
        case .fileNotFound:
            return "File not found"
        case .permissionDenied:
            return "Permission denied"
        case .invalidPath:
            return "Invalid path"
        case .pathAlreadyExists(let path):
            return "Path already exists: \(path). The file was skipped or renamed."
        case .revertInProgress:
            return "A revert operation is already in progress"
        }
    }
}

// MARK: - Duplicate Restoration Manager

/// Manages the persistence and restoration of safely deleted duplicates
@MainActor
public class DuplicateRestorationManager: ObservableObject {
    @Published public private(set) var restoredItems: [RestorableDuplicate] = []
    
    private let fileManager = FileManager.default
    private let persistenceKey = "DuplicateRestorationHistory"
    
    public static let shared = DuplicateRestorationManager()
    
    private init() {
        loadHistory()
    }
    
    /// Safely delete a list of duplicate files, keeping one original.
    /// Stores metadata for the deleted files so they can be "restored" by copying the original back.
    /// - Parameters:
    ///   - filesToDelete: The duplicates to remove
    ///   - originalFile: The file that is being kept (source for restoration)
    /// - Returns: A list of RestorableDuplicate objects representing the deleted files
    public func deleteSafely(filesToDelete: [FileItem], originalFile: FileItem) throws -> [RestorableDuplicate] {
        var deletedItems: [RestorableDuplicate] = []
        
        for file in filesToDelete {
            // Capture metadata before deletion
            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
            let metadata = RestorableDuplicate.FileMetadata(
                creationDate: attributes?[.creationDate] as? Date,
                modificationDate: attributes?[.modificationDate] as? Date,
                permissions: attributes?[.posixPermissions] as? Int,
                ownerAccountID: attributes?[.ownerAccountID] as? Int,
                groupOwnerAccountID: attributes?[.groupOwnerAccountID] as? Int
            )
            
            let item = RestorableDuplicate(
                originalPath: originalFile.path,
                deletedPath: file.path,
                metadata: metadata
            )
            
            // Perform Deletion
            try fileManager.removeItem(atPath: file.path)
            
            deletedItems.append(item)
        }
        
        restoredItems.append(contentsOf: deletedItems)
        saveHistory()
        
        return deletedItems
    }
    
    /// Restore a previously deleted duplicate
    public func restore(item: RestorableDuplicate) throws {
        // 1. Verify original still exists
        guard fileManager.fileExists(atPath: item.originalPath) else {
            throw RestorationError.originalFileNotFound
        }
        
        // 2. Verify target location is free (or handle overwrite?)
        if fileManager.fileExists(atPath: item.deletedPath) {
            throw RestorationError.targetLocationOccupied
        }
        
        // 3. Copy original to deleted path
        try fileManager.copyItem(atPath: item.originalPath, toPath: item.deletedPath)
        
        // 4. Apply metadata
        var attributes: [FileAttributeKey: Any] = [:]
        if let creation = item.metadata.creationDate { attributes[.creationDate] = creation }
        if let modification = item.metadata.modificationDate { attributes[.modificationDate] = modification }
        if let perms = item.metadata.permissions { attributes[.posixPermissions] = perms }
        if let owner = item.metadata.ownerAccountID { attributes[.ownerAccountID] = owner }
        if let group = item.metadata.groupOwnerAccountID { attributes[.groupOwnerAccountID] = group }
        
        try fileManager.setAttributes(attributes, ofItemAtPath: item.deletedPath)
        
        // 5. Remove from our tracking list since it's restored
        if let index = restoredItems.firstIndex(where: { $0.id == item.id }) {
            restoredItems.remove(at: index)
            saveHistory()
        }
    }
    
    /// Delete all stored history data
    public func clearAllData() {
        restoredItems.removeAll()
        UserDefaults.standard.removeObject(forKey: persistenceKey)
    }
    
    private func loadHistory() {
        if let data = UserDefaults.standard.data(forKey: persistenceKey),
           let decoded = try? JSONDecoder().decode([RestorableDuplicate].self, from: data) {
            restoredItems = decoded
        }
    }
    
    private func saveHistory() {
        if let encoded = try? JSONEncoder().encode(restoredItems) {
            UserDefaults.standard.set(encoded, forKey: persistenceKey)
        }
    }
    
    enum RestorationError: LocalizedError {
        case originalFileNotFound
        case targetLocationOccupied
        
        var errorDescription: String? {
            switch self {
            case .originalFileNotFound:
                return "The original file copy could not be found. It may have been moved or deleted."
            case .targetLocationOccupied:
                return "A file already exists at the restoration location."
            }
        }
    }
}

