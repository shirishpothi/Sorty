//
//  FileSystemManager.swift
//  Sorty
//
//  Safe file operations with undo tracking, conflict handling, and improved revert support
//  Fixed: History revert now properly handles all operations and prevents re-organization
//

import Foundation
import Combine
import Darwin

public actor FileSystemManager {
    private var undoStack: [FileOperation] = []
    private let fileManager = FileManager.default
    private var activeBookmarks: [URL: URL] = [:]

    // Track files that are currently being reverted to prevent re-organization
    private var revertingPaths: Set<String> = []

    // MARK: - Cross-Volume Move Optimization

    private var crossVolumeProgressHandler: (@Sendable (String, Double) -> Void)?

    private static let crossVolumeChunkSize: Int = 1_024 * 1_024 * 4 // 4 MB
    private static let largeFileThreshold: UInt64 = 50 * 1_024 * 1_024 // 50 MB

    public func setCrossVolumeProgressHandler(_ handler: (@Sendable (String, Double) -> Void)?) {
        crossVolumeProgressHandler = handler
    }

    private func isCrossVolume(from source: URL, to destination: URL) -> Bool {
        let sourceValues = try? source.resourceValues(forKeys: [.volumeIdentifierKey])
        let destinationParent = destination.deletingLastPathComponent()
        let destValues = try? destinationParent.resourceValues(forKeys: [.volumeIdentifierKey])

        guard let sourceVolume = sourceValues?.volumeIdentifier as? NSObject,
              let destVolume = destValues?.volumeIdentifier as? NSObject else {
            return false
        }

        return !sourceVolume.isEqual(destVolume)
    }

    private func copyWithProgress(from source: URL, to destination: URL, progressHandler: (@Sendable (Double) -> Void)?) async throws {
        let sourceAttributes = try fileManager.attributesOfItem(atPath: source.path)
        let fileSize = (sourceAttributes[.size] as? UInt64) ?? 0

        if fileSize > Self.largeFileThreshold {
            guard let readHandle = FileHandle(forReadingAtPath: source.path) else {
                throw FileSystemError.fileNotFound
            }
            defer { try? readHandle.close() }

            fileManager.createFile(atPath: destination.path, contents: nil)
            guard let writeHandle = FileHandle(forWritingAtPath: destination.path) else {
                throw FileSystemError.permissionDenied
            }
            defer { try? writeHandle.close() }

            var bytesWritten: UInt64 = 0
            while true {
                let chunk = readHandle.readData(ofLength: Self.crossVolumeChunkSize)
                if chunk.isEmpty { break }
                writeHandle.write(chunk)
                bytesWritten += UInt64(chunk.count)
                let progress = Double(bytesWritten) / Double(fileSize)
                progressHandler?(min(progress, 1.0))
            }
        } else {
            try fileManager.copyItem(at: source, to: destination)
            progressHandler?(1.0)
        }

        let destAttributes = try fileManager.attributesOfItem(atPath: destination.path)
        let destSize = (destAttributes[.size] as? UInt64) ?? 0
        guard destSize == fileSize else {
            try? fileManager.removeItem(at: destination)
            throw FileSystemError.crossVolumeCopyVerificationFailed(source.path)
        }

        try fileManager.removeItem(at: source)
    }

    /// Start accessing a security-scoped resource and track it
    private func startAccessing(_ url: URL) -> Bool {
        if url.startAccessingSecurityScopedResource() {
            activeBookmarks[url] = url
            return true
        }
        return false
    }

    /// Resolve folder destinations, including absolute storage locations.
    private func resolveDestinationFolderURL(
        folderName: String,
        parentURL: URL,
        requestSecurityScope: Bool = true
    ) -> URL {
        if let absoluteURL = StorageLocationPathResolver.absoluteURL(from: folderName) {
            if requestSecurityScope {
                _ = startAccessing(absoluteURL)
            }
            return absoluteURL
        }

        let sanitizedName = folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let directURL = parentURL.appendingPathComponent(sanitizedName, isDirectory: true)

        // If exact path exists as a directory, use it
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: directURL.path, isDirectory: &isDir) && isDir.boolValue {
            return directURL
        }

        // Fuzzy match: find existing directory with similar name (ignoring spaces/case)
        if let matchURL = findSimilarDirectory(named: sanitizedName, in: parentURL) {
            DebugLogger.log("Fuzzy matched folder '\(sanitizedName)' → existing '\(matchURL.lastPathComponent)'")
            return matchURL
        }

        return directURL
    }

    private func findSimilarDirectory(named name: String, in parentURL: URL) -> URL? {
        let normalized = name.lowercased().filter { $0.isLetter || $0.isNumber }
        guard !normalized.isEmpty else { return nil }

        guard let items = try? fileManager.contentsOfDirectory(
            at: parentURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        for item in items {
            guard let values = try? item.resourceValues(forKeys: [.isDirectoryKey]),
                  values.isDirectory == true else { continue }

            let itemNormalized = item.lastPathComponent.lowercased().filter { $0.isLetter || $0.isNumber }
            if itemNormalized == normalized {
                return item
            }
        }

        return nil
    }

    /// Stop accessing all tracked security-scoped resources
    private func stopAccessingAll() {
        for url in activeBookmarks.keys {
            url.stopAccessingSecurityScopedResource()
        }
        activeBookmarks.removeAll()
    }

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
            public var originalComment: String?
            public var newComment: String?

            public init(
                originalFilename: String? = nil,
                newFilename: String? = nil,
                wasCreatedDuringOrganization: Bool = false,
                parentFolderPath: String? = nil,
                originalTags: [String]? = nil,
                newTags: [String]? = nil,
                originalComment: String? = nil,
                newComment: String? = nil
            ) {
                self.originalFilename = originalFilename
                self.newFilename = newFilename
                self.wasCreatedDuringOrganization = wasCreatedDuringOrganization
                self.parentFolderPath = parentFolderPath
                self.originalTags = originalTags
                self.newTags = newTags
                self.originalComment = originalComment
                self.newComment = newComment
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
    
    /// Result of a restore/undo operation
    public struct RestoreResult: Sendable {
        public let successfulOperations: Int
        public let missingFiles: [String]  // File paths that couldn't be restored because they no longer exist
        
        public var hasIssues: Bool { !missingFiles.isEmpty }
        
        public var summaryMessage: String {
            if missingFiles.isEmpty {
                return "Successfully restored \(successfulOperations) operations."
            } else {
                return "Restored \(successfulOperations) operations. \(missingFiles.count) file(s) couldn't be restored because they no longer exist."
            }
        }
    }

    public init() {}

    // MARK: - Revert Protection

    /// Check if a path is currently being reverted
    public func isPathBeingReverted(_ path: String) -> Bool {
        return revertingPaths.contains(path) || revertingPaths.contains { path.isSubpath(of: $0) }
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

    func createFolders(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false, exclusionManager: ExclusionRulesManager? = nil) async throws -> [FileOperation] {
        var operations: [FileOperation] = []

        for suggestion in plan.suggestions {
            let ops = try await createFolderRecursive(suggestion, parentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: ops)
        }

        return operations
    }
    
    private func createFolderRecursive(_ suggestion: FolderSuggestion, parentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager?) async throws -> [FileOperation] {
        var operations: [FileOperation] = []
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: parentURL)

        // Check exclusions
        if let manager = exclusionManager {
            let item = FileItem(path: folderURL.path, name: folderURL.lastPathComponent, extension: folderURL.pathExtension)
            if await manager.shouldExclude(item) {
                DebugLogger.log("Skipping excluded folder creation: \(folderURL.path)")
                return operations
            }
        }

        if !dryRun {
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    // Folder already exists, continue with subfolders
                } else {
                    // Conflict: File exists where folder should be
                    let backupBaseName = folderURL.lastPathComponent
                    let backupURL = folderURL.deletingLastPathComponent()
                        .appendingPathComponent("\(backupBaseName)_file_backup_\(UUID().uuidString.prefix(8))")
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
            let subOps = try await createFolderRecursive(subfolder, parentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: subOps)
        }
        
        return operations
    }

    // MARK: - File Moving with Rename Support

    func moveFiles(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false, exclusionManager: ExclusionRulesManager? = nil) async throws -> [FileOperation] {
        var operations: [FileOperation] = []

        for suggestion in plan.suggestions {
            let ops = try await moveFilesInSuggestion(suggestion, parentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: ops)
        }

        return operations
    }
    
    private func moveFilesInSuggestion(_ suggestion: FolderSuggestion, parentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager?) async throws -> [FileOperation] {
        var operations: [FileOperation] = []
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: parentURL)

        // Process files with potential renaming
        for file in suggestion.files {
            guard let sourceURL = file.url else { continue }

            // Check exclusions
            if let manager = exclusionManager {
                if await manager.shouldExclude(file) {
                    DebugLogger.log("Skipping excluded file move: \(sourceURL.path)")
                    continue
                }
            }

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

                // Move file — use cross-volume copy+delete when source and destination are on different volumes
                if isCrossVolume(from: sourceURL, to: destinationURL) {
                    DebugLogger.log("Cross-volume move detected: \(sourceURL.path) → \(destinationURL.path)")
                    let fileName = sourceURL.lastPathComponent
                    let handler = crossVolumeProgressHandler
                    try await copyWithProgress(from: sourceURL, to: destinationURL) { progress in
                        handler?(fileName, progress)
                    }
                } else {
                    try fileManager.moveItem(at: sourceURL, to: destinationURL)
                }
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
            let subOps = try await moveFilesInSuggestion(subfolder, parentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: subOps)
        }
        
        return operations
    }

    // MARK: - Conflict Detection

    public func detectConflicts(for plan: OrganizationPlan, at baseURL: URL) async -> [FileConflict] {
        var conflicts: [FileConflict] = []

        for suggestion in plan.suggestions {
            let found = detectConflictsInSuggestion(suggestion, parentURL: baseURL)
            conflicts.append(contentsOf: found)
        }

        return conflicts
    }

    private func detectConflictsInSuggestion(_ suggestion: FolderSuggestion, parentURL: URL) -> [FileConflict] {
        var conflicts: [FileConflict] = []

        let folderURL = resolveDestinationFolderURL(
            folderName: suggestion.folderName,
            parentURL: parentURL,
            requestSecurityScope: false
        )

        for file in suggestion.files {
            guard let sourceURL = file.url else { continue }

            let finalFilename: String
            if let mapping = suggestion.renameMapping(for: file), mapping.hasRename, let newName = mapping.suggestedName {
                finalFilename = newName
            } else {
                finalFilename = sourceURL.lastPathComponent
            }

            let destinationURL = folderURL.appendingPathComponent(finalFilename)

            if sourceURL.standardizedFileURL.path == destinationURL.standardizedFileURL.path {
                continue
            }

            if fileManager.fileExists(atPath: destinationURL.path) {
                let sourceAttrs = try? fileManager.attributesOfItem(atPath: sourceURL.path)
                let destAttrs = try? fileManager.attributesOfItem(atPath: destinationURL.path)

                let conflict = FileConflict(
                    sourceURL: sourceURL,
                    destinationURL: destinationURL,
                    sourceName: sourceURL.lastPathComponent,
                    destinationName: destinationURL.lastPathComponent,
                    sourceSize: (sourceAttrs?[.size] as? Int64) ?? file.size,
                    destinationSize: (destAttrs?[.size] as? Int64) ?? 0,
                    sourceDate: sourceAttrs?[.modificationDate] as? Date,
                    destinationDate: destAttrs?[.modificationDate] as? Date
                )
                conflicts.append(conflict)
            }
        }

        for subfolder in suggestion.subfolders {
            let subConflicts = detectConflictsInSuggestion(subfolder, parentURL: folderURL)
            conflicts.append(contentsOf: subConflicts)
        }

        return conflicts
    }

    // MARK: - File Tagging

    func tagFiles(_ plan: OrganizationPlan, at baseURL: URL, dryRun: Bool = false, exclusionManager: ExclusionRulesManager? = nil) async throws -> [FileOperation] {
        // Tagging is now gated by the caller using this method
        var operations: [FileOperation] = []

        for suggestion in plan.suggestions {
            let ops = try await tagFilesInSuggestion(suggestion, parentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: ops)
        }

        return operations
    }
    
    private func normalizeFinderTag(_ tag: String) -> String {
        switch tag.lowercased() {
        case "important", "urgent", "critical", "high priority":
            return "Red"
        case "in progress", "pending", "todo", "needs attention", "review":
            return "Orange"
        case "draft", "temporary", "temp", "wip":
            return "Yellow"
        case "complete", "done", "verified", "approved", "final":
            return "Green"
        case "reference", "info", "documentation", "docs":
            return "Blue"
        case "creative", "design", "media", "art":
            return "Purple"
        case "archive", "old", "inactive", "deprecated":
            return "Gray"
        case "red", "orange", "yellow", "green", "blue", "purple", "gray":
            return tag.capitalized
        default:
            return tag
        }
    }

    private func setFinderComment(_ comment: String?, for url: URL) throws {
        let path = url.path
        let key = "com.apple.metadata:kMDItemFinderComment"

        guard let comment = comment, !comment.isEmpty else {
            let rc = removexattr(path, key, 0)
            if rc != 0 && errno != 93 {
                DebugLogger.log("Failed to remove Finder comment for \(path): errno \(errno)")
            }
            return
        }

        let data = try PropertyListSerialization.data(
            fromPropertyList: comment,
            format: .binary,
            options: 0
        )

        let rc: Int32 = data.withUnsafeBytes { buf in
            setxattr(path, key, buf.baseAddress!, buf.count, 0, 0)
        }
        if rc != 0 {
            DebugLogger.log("Failed to set Finder comment for \(path): errno \(errno)")
        }
    }

    private func getFinderComment(for url: URL) -> String? {
        let path = url.path
        let key = "com.apple.metadata:kMDItemFinderComment"

        let size = getxattr(path, key, nil, 0, 0, 0)
        guard size > 0 else { return nil }

        var data = Data(count: size)
        let result = data.withUnsafeMutableBytes { buf in
            getxattr(path, key, buf.baseAddress, size, 0, 0)
        }
        guard result > 0 else { return nil }

        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? String
    }

    private func applyTagsAndComment(to url: URL, tags: [String], comment: String?, dryRun: Bool) -> FileOperation? {
        let hasComment = comment != nil && !(comment ?? "").isEmpty
        guard !tags.isEmpty || hasComment else { return nil }

        if dryRun {
            return FileOperation(
                type: .tagFile,
                sourcePath: url.path,
                destinationPath: nil,
                metadata: FileOperation.OperationMetadata(
                    newTags: tags,
                    newComment: comment
                )
            )
        }

        guard fileManager.fileExists(atPath: url.path) else { return nil }

        let resourceValues = try? url.resourceValues(forKeys: [.tagNamesKey])
        let originalTags = resourceValues?.tagNames ?? []
        let originalComment = getFinderComment(for: url)

        var finalTags = originalTags
        if !tags.isEmpty {
            let normalizedTags = tags.map { normalizeFinderTag($0) }
            var newTagsSet = Set(originalTags)
            for tag in normalizedTags {
                newTagsSet.insert(tag)
            }
            finalTags = Array(newTagsSet)

            let nsURL = url as NSURL
            do {
                try nsURL.setResourceValue(finalTags, forKey: .tagNamesKey)
                #if DEBUG
                if let verifyValues = try? url.resourceValues(forKeys: [.tagNamesKey]),
                   let verifyTags = verifyValues.tagNames {
                    DebugLogger.log("Tags verified for \(url.lastPathComponent): \(verifyTags)")
                }
                #endif
            } catch {
                DebugLogger.log("Tagging failed for \(url.path): \(error.localizedDescription)")
            }
        }

        if hasComment {
            try? setFinderComment(comment, for: url)
        }

        return FileOperation(
            type: .tagFile,
            sourcePath: url.path,
            destinationPath: nil,
            metadata: FileOperation.OperationMetadata(
                originalTags: originalTags,
                newTags: finalTags,
                originalComment: originalComment,
                newComment: comment
            )
        )
    }

    private func tagFilesInSuggestion(_ suggestion: FolderSuggestion, parentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager?) async throws -> [FileOperation] {
        var operations: [FileOperation] = []
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: parentURL)

        if let folderOp = applyTagsAndComment(to: folderURL, tags: suggestion.tags, comment: suggestion.comment, dryRun: dryRun) {
            operations.append(folderOp)
        }

        // Look for tag mappings in this suggestion
        for mapping in suggestion.fileTagMappings {
            // Check exclusions
            if let manager = exclusionManager {
                if await manager.shouldExclude(mapping.originalFile) {
                    continue
                }
            }

            // Find the file name (use the new name if it was renamed)
            let finalFilename = suggestion.filesWithFinalNames.first(where: { $0.file.id == mapping.originalFile.id })?.finalName ?? mapping.originalFile.displayName
            
            let fileURL = folderURL.appendingPathComponent(finalFilename)
            
            if let op = applyTagsAndComment(to: fileURL, tags: mapping.tags, comment: mapping.comment, dryRun: dryRun) {
                operations.append(op)
            }
        }

        // Recurse
        for subfolder in suggestion.subfolders {
            let subOps = try await tagFilesInSuggestion(subfolder, parentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager)
            operations.append(contentsOf: subOps)
        }
        
        return operations
    }

    // MARK: - Apply Organization
    
    func validateOperation(_ operation: FileOperation, exclusionManager: ExclusionRulesManager?) async -> Bool {
        guard let manager = exclusionManager else { return true }
        
        let sourceURL = URL(fileURLWithPath: operation.sourcePath)
        let sourceItem = FileItem(path: sourceURL.path, name: sourceURL.lastPathComponent, extension: sourceURL.pathExtension)
        
        let shouldExcludeSource = await manager.shouldExclude(sourceItem)
        if shouldExcludeSource {
            DebugLogger.log("Operation BLOCKED: Source \(operation.sourcePath) is excluded.")
            return false
        }
        
        if let destPath = operation.destinationPath {
            let destURL = URL(fileURLWithPath: destPath)
            let destItem = FileItem(path: destURL.path, name: destURL.lastPathComponent, extension: destURL.pathExtension)
            let shouldExcludeDest = await manager.shouldExclude(destItem)
            if shouldExcludeDest {
                DebugLogger.log("Operation BLOCKED: Destination \(destPath) is excluded.")
                return false
            }
        }
        
        return true
    }

    private struct OperationResult {
        let operations: [FileOperation]
        let processedCount: Int
    }
    
    public struct ApplyOrganizationResult: Sendable {
        public let operations: [FileOperation]
        public let failures: [OperationFailure]
        public let totalAttempted: Int
        
        public var successCount: Int { operations.filter { $0.type == .moveFile || $0.type == .renameFile }.count }
        public var failureCount: Int { failures.count }
        public var hasFailures: Bool { !failures.isEmpty }
    }

    func applyOrganization(
        _ plan: OrganizationPlan, 
        at baseURL: URL, 
        dryRun: Bool = false, 
        enableTagging: Bool = true,
        strictExclusions: Bool = true,
        exclusionManager: ExclusionRulesManager? = nil,
        progress: (@Sendable (Double, String) -> Void)? = nil
    ) async throws -> [FileOperation] {
        _ = startAccessing(baseURL)
        defer { stopAccessingAll() }

        var allOperations: [FileOperation] = []
        var allFailures: [OperationFailure] = []
        
        let totalFiles = plan.suggestions.reduce(0) { $0 + countFiles(in: $1) }
        let totalFolders = plan.suggestions.reduce(0) { $0 + countFolders(in: $1) }
        let totalOps = totalFiles + totalFolders + (enableTagging ? totalFiles + totalFolders : 0)
        var completedOps = 0
        
        func updateProgress(_ message: String) {
            completedOps += 1
            let raw = totalOps > 0 ? Double(completedOps) / Double(totalOps) : 1.0
            progress?(min(raw, 1.0), message)
        }

        if !dryRun {
            progress?(0.02, "Validating files...")
            let validationIssues = await preValidatePlan(plan, at: baseURL)
            if !validationIssues.isEmpty {
                DebugLogger.log("Pre-validation found \(validationIssues.count) issue(s): \(validationIssues.joined(separator: ", "))")
            }
        }

        progress?(0.05, "Creating folder structure...")
        
        for suggestion in plan.suggestions {
            let result = try await createFoldersWithProgress(suggestion, currentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager, onProgress: { message in
                updateProgress(message)
            }, failures: &allFailures)
            allOperations.append(contentsOf: result.operations)
        }

        progress?(0.1, "Moving files...")
        
        for suggestion in plan.suggestions {
            let result = try await moveFilesInSuggestionWithProgress(suggestion, parentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager, onProgress: { message in
                updateProgress(message)
            }, failures: &allFailures)
            allOperations.append(contentsOf: result.operations)
        }

        if enableTagging {
            progress?(0.8, "Applying tags...")
            
            for suggestion in plan.suggestions {
                let result = try await tagFilesWithProgress(suggestion, currentURL: baseURL, dryRun: dryRun, exclusionManager: exclusionManager) { message in
                    updateProgress(message)
                }
                allOperations.append(contentsOf: result.operations)
            }
        }

        if !dryRun {
            progress?(0.9, "Cleaning up empty folders...")
            undoStack.append(contentsOf: allOperations)
            
            let fileOps = allOperations.filter { $0.type == .moveFile || $0.type == .renameFile }
            let sourceFolders = Set(fileOps.compactMap { URL(fileURLWithPath: $0.sourcePath).deletingLastPathComponent().path })
            let sortedFolders = sourceFolders.sorted { $0.components(separatedBy: "/").count > $1.components(separatedBy: "/").count }

            for folderPath in sortedFolders {
                if folderPath != baseURL.path && folderPath.hasPrefix(baseURL.path) {
                    try? removeEmptyFolder(at: folderPath)
                }
            }
            
            var newlyCreatedFolders = Set<String>()
            for suggestion in plan.suggestions {
                let paths = collectFolderPaths(suggestion, parentURL: baseURL)
                newlyCreatedFolders.formUnion(paths)
            }
            try? cleanupEmptySubdirectories(at: baseURL, excluding: newlyCreatedFolders)
            
            if !allFailures.isEmpty {
                DebugLogger.log("Organization completed with \(allFailures.count) failure(s)")
                for failure in allFailures {
                    DebugLogger.log("  - \(failure.sourcePath): \(failure.error)")
                }
            }
        }
        
        let successCount = allOperations.filter { $0.type == .moveFile || $0.type == .renameFile }.count
        if allFailures.isEmpty {
            progress?(1.0, "Organization complete!")
        } else {
            progress?(1.0, "Complete with \(allFailures.count) skipped file(s)")
        }
        
        return allOperations
    }
    
    private func createFoldersWithProgress(_ suggestion: FolderSuggestion, currentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager? = nil, onProgress: (String) -> Void, failures: inout [OperationFailure]) async throws -> OperationResult {
        var operations: [FileOperation] = []
        var processedCount = 0
        
        try Task.checkCancellation()
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: currentURL)
        
        if let manager = exclusionManager {
            let item = FileItem(path: folderURL.path, name: folderURL.lastPathComponent, extension: folderURL.pathExtension)
            if await manager.shouldExclude(item) {
                DebugLogger.log("Skipping excluded folder creation: \(folderURL.path)")
                return OperationResult(operations: operations, processedCount: processedCount)
            }
        }
        
        if !dryRun {
            var isDirectory: ObjCBool = false
            let exists = fileManager.fileExists(atPath: folderURL.path, isDirectory: &isDirectory)
            
            do {
                if exists && !isDirectory.boolValue {
                    let backupName = "\(folderURL.lastPathComponent)_backup_\(UUID().uuidString.prefix(8))"
                    let backupURL = currentURL.appendingPathComponent(backupName)
                    try await withRetry {
                        try fileManager.moveItem(at: folderURL, to: backupURL)
                    }
                    DebugLogger.log("Moved conflicting file to \(backupName)")
                }
                
                if !exists || !isDirectory.boolValue {
                    try await withRetry {
                        try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                    }
                    operations.append(FileOperation(
                        type: .createFolder,
                        sourcePath: folderURL.path,
                        destinationPath: nil,
                        metadata: .init(wasCreatedDuringOrganization: true)
                    ))
                }
            } catch {
                DebugLogger.log("Failed to create folder \(folderURL.path): \(error.localizedDescription)")
                failures.append(OperationFailure(
                    sourcePath: folderURL.path,
                    destinationPath: nil,
                    error: error.localizedDescription,
                    isRetryable: false
                ))
                onProgress("Skipped folder \(suggestion.folderName) (permission denied)...")
                processedCount += 1
                return OperationResult(operations: operations, processedCount: processedCount)
            }
        }
        onProgress("Creating folder \(suggestion.folderName)...")
        processedCount += 1
        
        for subfolder in suggestion.subfolders {
            let subResult = try await createFoldersWithProgress(subfolder, currentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager, onProgress: onProgress, failures: &failures)
            operations.append(contentsOf: subResult.operations)
            processedCount += subResult.processedCount
        }
        
        return OperationResult(operations: operations, processedCount: processedCount)
    }
    
    private func moveFilesInSuggestionWithProgress(_ suggestion: FolderSuggestion, parentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager? = nil, onProgress: (String) -> Void, failures: inout [OperationFailure]) async throws -> OperationResult {
        var operations: [FileOperation] = []
        var processedCount = 0
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: parentURL)

        for file in suggestion.files {
            try Task.checkCancellation()
            guard let sourceURL = file.url else { continue }
            
            if let manager = exclusionManager {
                if await manager.shouldExclude(file) {
                    DebugLogger.log("Skipping excluded file move: \(sourceURL.path)")
                    onProgress("Skipped \(sourceURL.lastPathComponent) (excluded)...")
                    processedCount += 1
                    continue
                }
            }
            
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
            
            if sourceURL.standardizedFileURL.path != destinationURL.standardizedFileURL.path {
                if !dryRun {
                    do {
                        if !fileManager.fileExists(atPath: folderURL.path) {
                            try await withRetry {
                                try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true)
                            }
                        }
                        if fileManager.fileExists(atPath: destinationURL.path) {
                            destinationURL = generateUniqueURL(for: destinationURL)
                        }
                        
                        guard fileManager.fileExists(atPath: sourceURL.path) else {
                            failures.append(OperationFailure(
                                sourcePath: sourceURL.path,
                                destinationPath: destinationURL.path,
                                error: "Source file no longer exists",
                                isRetryable: false
                            ))
                            onProgress("Skipped \(finalFilename) (not found)...")
                            processedCount += 1
                            continue
                        }
                        
                        if isCrossVolume(from: sourceURL, to: destinationURL) {
                            DebugLogger.log("Cross-volume move detected: \(sourceURL.path) → \(destinationURL.path)")
                            let fileName = sourceURL.lastPathComponent
                            let handler = crossVolumeProgressHandler
                            try await copyWithProgress(from: sourceURL, to: destinationURL) { progress in
                                handler?(fileName, progress)
                            }
                        } else {
                            try await withRetry {
                                try fileManager.moveItem(at: sourceURL, to: destinationURL)
                            }
                        }
                        
                        let operationType: FileOperation.OperationType = renameMetadata != nil ? .renameFile : .moveFile
                        operations.append(FileOperation(
                            id: UUID(),
                            type: operationType,
                            sourcePath: sourceURL.path,
                            destinationPath: destinationURL.path,
                            timestamp: Date(),
                            metadata: renameMetadata
                        ))
                    } catch {
                        let isRetryable = isRetryableError(error)
                        failures.append(OperationFailure(
                            sourcePath: sourceURL.path,
                            destinationPath: destinationURL.path,
                            error: error.localizedDescription,
                            isRetryable: isRetryable
                        ))
                        DebugLogger.log("Failed to move \(sourceURL.lastPathComponent): \(error.localizedDescription)")
                    }
                } else {
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
            }
            
            onProgress("Moving \(finalFilename)...")
            processedCount += 1
        }

        for subfolder in suggestion.subfolders {
            let subResult = try await moveFilesInSuggestionWithProgress(subfolder, parentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager, onProgress: onProgress, failures: &failures)
            operations.append(contentsOf: subResult.operations)
            processedCount += subResult.processedCount
        }
        
        return OperationResult(operations: operations, processedCount: processedCount)
    }
    
    private func tagFilesWithProgress(_ suggestion: FolderSuggestion, currentURL: URL, dryRun: Bool, exclusionManager: ExclusionRulesManager? = nil, onProgress: (String) -> Void) async throws -> OperationResult {
        var operations: [FileOperation] = []
        var processedCount = 0
        
        try Task.checkCancellation()
        
        let folderURL = resolveDestinationFolderURL(folderName: suggestion.folderName, parentURL: currentURL)

        if let folderOp = applyTagsAndComment(to: folderURL, tags: suggestion.tags, comment: suggestion.comment, dryRun: dryRun) {
            operations.append(folderOp)
            onProgress("Tagging \(suggestion.folderName)...")
            processedCount += 1
        }
        
        for mapping in suggestion.fileTagMappings {
            try Task.checkCancellation()
            
            if let manager = exclusionManager {
                if await manager.shouldExclude(mapping.originalFile) {
                    continue
                }
            }
            
            let finalFilename = suggestion.filesWithFinalNames.first(where: { $0.file.id == mapping.originalFile.id })?.finalName ?? mapping.originalFile.displayName
            let fileURL = folderURL.appendingPathComponent(finalFilename)
            
            if let op = applyTagsAndComment(to: fileURL, tags: mapping.tags, comment: mapping.comment, dryRun: dryRun) {
                operations.append(op)
            }
            onProgress("Tagging \(finalFilename)...")
            processedCount += 1
        }
        
        for subfolder in suggestion.subfolders {
            let subResult = try await tagFilesWithProgress(subfolder, currentURL: folderURL, dryRun: dryRun, exclusionManager: exclusionManager, onProgress: onProgress)
            operations.append(contentsOf: subResult.operations)
            processedCount += subResult.processedCount
        }
        
        return OperationResult(operations: operations, processedCount: processedCount)
    }
    
    private func collectFolderPaths(_ suggestion: FolderSuggestion, parentURL: URL) -> Set<String> {
        var paths = Set<String>()
        let folderURL = resolveDestinationFolderURL(
            folderName: suggestion.folderName,
            parentURL: parentURL,
            requestSecurityScope: false
        )
        paths.insert(folderURL.path)
        for subfolder in suggestion.subfolders {
            let subPaths = collectFolderPaths(subfolder, parentURL: folderURL)
            paths.formUnion(subPaths)
        }
        return paths
    }
    
    private func countFiles(in folder: FolderSuggestion) -> Int {
        return folder.files.count + folder.subfolders.reduce(0) { $0 + countFiles(in: $1) }
    }
    
    private func countFolders(in folder: FolderSuggestion) -> Int {
        return 1 + folder.subfolders.reduce(0) { $0 + countFolders(in: $1) }
    }
    
    /// Recursively find and remove empty subdirectories, excluding newly created folders
    private func cleanupEmptySubdirectories(at baseURL: URL, excluding protectedPaths: Set<String>) throws {
        let contents = try fileManager.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: [.isDirectoryKey])
        
        for item in contents {
            // Skip hidden files/folders
            if item.lastPathComponent.hasPrefix(".") {
                continue
            }
            
            // Skip if this is one of the newly created folders (we want to keep those)
            if protectedPaths.contains(item.path) {
                continue
            }
            
            let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
            let isDirectory = resourceValues?.isDirectory ?? false
            
            if isDirectory {
                // Recursively clean up subdirectories first
                try? cleanupEmptySubdirectories(at: item, excluding: protectedPaths)
                
                // Then try to remove this folder if it's empty
                try? removeEmptyFolder(at: item.path)
            }
        }
    }

    // MARK: - Reverse Operations (Undo/Revert)
    
    /// Pre-flight check for restore operations - returns list of files that are missing at destination
    func preflightRestore(_ operations: [FileOperation]) -> [String] {
        var missingFiles: [String] = []
        
        for operation in operations {
            switch operation.type {
            case .moveFile, .renameFile:
                if let destinationPath = operation.destinationPath {
                    if !fileManager.fileExists(atPath: destinationPath) {
                        // File no longer exists at destination - can't restore
                        missingFiles.append(URL(fileURLWithPath: destinationPath).lastPathComponent)
                    }
                }
            case .createFolder, .deleteFile, .copyFile, .tagFile:
                // These don't require the file to exist for undo
                break
            }
        }
        
        return missingFiles
    }

    /// Reverses a set of operations - returns result with details about skipped files
    func reverseOperations(_ operations: [FileOperation]) async throws -> RestoreResult {
        // Collect all paths involved and ensure we have access if they are security-scoped
        var involvedPaths: [String] = []
        for op in operations {
            involvedPaths.append(op.sourcePath)
            if let dest = op.destinationPath {
                involvedPaths.append(dest)
            }
        }
        
        // Start accessing all involved paths that might be security-scoped
        for path in involvedPaths {
            _ = startAccessing(URL(fileURLWithPath: path))
        }
        defer { stopAccessingAll() }

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
        
        // Track results
        var successCount = 0
        var missingFiles: [String] = []

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
                        successCount += 1

                        // Mark parent folder for potential cleanup
                        let parentFolder = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
                        foldersToCleanup.insert(parentFolder)
                    } else {
                        // File no longer exists - track as missing
                        let filename = URL(fileURLWithPath: destinationPath).lastPathComponent
                        missingFiles.append(filename)
                        DebugLogger.log("Cannot restore - file no longer exists: \(destinationPath)")
                    }
                }

            case .createFolder:
                // Mark for cleanup (will be handled in second pass)
                foldersToCleanup.insert(operation.sourcePath)
                successCount += 1

            case .deleteFile:
                // Cannot undo deletion without backup - log warning
                DebugLogger.log("Cannot undo deletion: \(operation.sourcePath)")
                missingFiles.append(URL(fileURLWithPath: operation.sourcePath).lastPathComponent)

            case .copyFile:
                // Remove the copy if it exists
                if let destinationPath = operation.destinationPath,
                   fileManager.fileExists(atPath: destinationPath) {
                    try fileManager.removeItem(atPath: destinationPath)
                    successCount += 1
                }
                
            case .tagFile:
                if let originalTags = operation.metadata?.originalTags {
                   let url = URL(fileURLWithPath: operation.sourcePath)
                   if fileManager.fileExists(atPath: url.path) {
                       let nsURL = url as NSURL
                       try? nsURL.setResourceValue(originalTags, forKey: .tagNamesKey)
                       successCount += 1
                   }
                }
                if operation.metadata?.newComment != nil {
                    let url = URL(fileURLWithPath: operation.sourcePath)
                    if fileManager.fileExists(atPath: url.path) {
                        try? setFinderComment(operation.metadata?.originalComment, for: url)
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
        
        return RestoreResult(successfulOperations: successCount, missingFiles: missingFiles)
    }

    /// Undoes a single file operation (move file back, remove created folder if empty, restore tags)
    public func restoreSingleOperation(_ operation: FileOperation) async throws -> RestoreResult {
        _ = startAccessing(URL(fileURLWithPath: operation.sourcePath))
        if let dest = operation.destinationPath {
            _ = startAccessing(URL(fileURLWithPath: dest))
        }
        defer { stopAccessingAll() }

        var successCount = 0
        var missingFiles: [String] = []

        switch operation.type {
        case .moveFile, .renameFile:
            if let destinationPath = operation.destinationPath {
                if fileManager.fileExists(atPath: destinationPath) {
                    let originalDir = URL(fileURLWithPath: operation.sourcePath).deletingLastPathComponent()
                    if !fileManager.fileExists(atPath: originalDir.path) {
                        try fileManager.createDirectory(at: originalDir, withIntermediateDirectories: true)
                    }

                    var finalSourcePath = operation.sourcePath
                    if fileManager.fileExists(atPath: finalSourcePath) {
                        let uniqueURL = generateUniqueURL(for: URL(fileURLWithPath: finalSourcePath))
                        finalSourcePath = uniqueURL.path
                    }

                    try fileManager.moveItem(atPath: destinationPath, toPath: finalSourcePath)
                    successCount += 1

                    let parentFolder = URL(fileURLWithPath: destinationPath).deletingLastPathComponent().path
                    try? removeEmptyFolder(at: parentFolder)
                } else {
                    let filename = URL(fileURLWithPath: destinationPath).lastPathComponent
                    missingFiles.append(filename)
                }
            }

        case .createFolder:
            try? removeEmptyFolder(at: operation.sourcePath)
            successCount += 1

        case .deleteFile:
            missingFiles.append(URL(fileURLWithPath: operation.sourcePath).lastPathComponent)

        case .copyFile:
            if let destinationPath = operation.destinationPath,
               fileManager.fileExists(atPath: destinationPath) {
                try fileManager.removeItem(atPath: destinationPath)
                successCount += 1
            }

        case .tagFile:
            let url = URL(fileURLWithPath: operation.sourcePath)
            if fileManager.fileExists(atPath: url.path) {
                if let originalTags = operation.metadata?.originalTags {
                    let nsURL = url as NSURL
                    try? nsURL.setResourceValue(originalTags, forKey: .tagNamesKey)
                }
                if operation.metadata?.newComment != nil {
                    try? setFinderComment(operation.metadata?.originalComment, for: url)
                }
                successCount += 1
            } else {
                missingFiles.append(url.lastPathComponent)
            }
        }

        return RestoreResult(successfulOperations: successCount, missingFiles: missingFiles)
    }

    /// Remove a folder only if it's empty (including cleaning up parent folders)
    private func removeEmptyFolder(at path: String) throws {
        guard fileManager.fileExists(atPath: path) else { return }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)

            // Safe list of disposable files
            let disposableFiles: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini"]
            
            // Check if there are any files that are NOT in the disposable list
            let hasSignificantContent = contents.contains { filename in
                !disposableFiles.contains(filename)
            }

            if !hasSignificantContent {
                // Only remove the known disposable files
                for item in contents {
                    if disposableFiles.contains(item) {
                        let itemPath = (path as NSString).appendingPathComponent(item)
                        try? fileManager.removeItem(atPath: itemPath)
                    }
                }

                // Double check if folder is truly empty now
                if let remaining = try? fileManager.contentsOfDirectory(atPath: path), remaining.isEmpty {
                     try fileManager.removeItem(atPath: path)
                }
                
                // Try to clean up parent folder too
                let parentPath = (path as NSString).deletingLastPathComponent
                try? removeEmptyFolder(at: parentPath)
                
                return // Exit function
            }

        } catch {
            // Folder might not be empty or we don't have permission
            DebugLogger.log("Could not remove folder: \(path) - \(error.localizedDescription)")
        }
    }

    // MARK: - Retry and Validation Helpers
    
    private struct RetryConfig {
        let maxAttempts: Int
        let baseDelay: UInt64
        let maxDelay: UInt64
        
        static let `default` = RetryConfig(
            maxAttempts: 3,
            baseDelay: 100_000_000, // 100ms
            maxDelay: 1_000_000_000 // 1s
        )
    }
    
    private func isRetryableError(_ error: Error) -> Bool {
        let nsError = error as NSError
        switch nsError.domain {
        case NSCocoaErrorDomain:
            switch nsError.code {
            case NSFileWriteNoPermissionError,
                 NSFileReadNoPermissionError:
                return false
            case 640, // NSFileBusyError constant value
                 NSFileWriteVolumeReadOnlyError:
                return true
            default:
                return nsError.code >= 500
            }
        case NSPOSIXErrorDomain:
            switch nsError.code {
            case Int(EBUSY), Int(EAGAIN), Int(EINTR), Int(ETXTBSY):
                return true
            case Int(EACCES), Int(EPERM), Int(EROFS):
                return false
            default:
                return false
            }
        default:
            return false
        }
    }
    
    private func withRetry<T>(
        config: RetryConfig = .default,
        operation: () throws -> T
    ) async throws -> T {
        var lastError: Error?
        var delay = config.baseDelay
        
        for attempt in 1...config.maxAttempts {
            do {
                return try operation()
            } catch {
                lastError = error
                
                if !isRetryableError(error) || attempt == config.maxAttempts {
                    throw error
                }
                
                DebugLogger.log("Retry attempt \(attempt)/\(config.maxAttempts) after error: \(error.localizedDescription)")
                try await Task.sleep(nanoseconds: delay)
                delay = min(delay * 2, config.maxDelay)
            }
        }
        
        throw lastError ?? FileSystemError.fileNotFound
    }
    
    private func checkFileAccessibility(at url: URL) -> (accessible: Bool, issue: String?) {
        let path = url.path
        
        guard fileManager.fileExists(atPath: path) else {
            return (false, "File does not exist: \(url.lastPathComponent)")
        }
        
        guard fileManager.isReadableFile(atPath: path) else {
            return (false, "Cannot read file: \(url.lastPathComponent)")
        }
        
        let resourceValues = try? url.resourceValues(forKeys: [.isWritableKey, .isReadableKey, .volumeIsReadOnlyKey])
        
        if resourceValues?.volumeIsReadOnly == true {
            return (false, "Volume is read-only for: \(url.lastPathComponent)")
        }
        
        return (true, nil)
    }
    
    private func checkDestinationWritable(at url: URL) -> (writable: Bool, issue: String?) {
        let parentDir = url.deletingLastPathComponent()
        let parentPath = parentDir.path
        
        if fileManager.fileExists(atPath: parentPath) {
            guard fileManager.isWritableFile(atPath: parentPath) else {
                return (false, "Cannot write to destination folder: \(parentDir.lastPathComponent)")
            }
        } else {
            var ancestorPath = parentPath
            while !fileManager.fileExists(atPath: ancestorPath) && ancestorPath != "/" {
                ancestorPath = (ancestorPath as NSString).deletingLastPathComponent
            }
            guard fileManager.isWritableFile(atPath: ancestorPath) else {
                return (false, "Cannot create destination folder: \(parentDir.lastPathComponent)")
            }
        }
        
        return (true, nil)
    }
    
    func preValidatePlan(_ plan: OrganizationPlan, at baseURL: URL) async -> [String] {
        var issues: [String] = []
        
        let baseCheck = checkDestinationWritable(at: baseURL)
        if !baseCheck.writable, let issue = baseCheck.issue {
            issues.append(issue)
        }
        
        for suggestion in plan.suggestions {
            let suggestionIssues = await preValidateSuggestion(suggestion, parentURL: baseURL)
            issues.append(contentsOf: suggestionIssues)
        }
        
        return issues
    }
    
    private func preValidateSuggestion(_ suggestion: FolderSuggestion, parentURL: URL) async -> [String] {
        var issues: [String] = []
        
        let folderURL = resolveDestinationFolderURL(
            folderName: suggestion.folderName,
            parentURL: parentURL,
            requestSecurityScope: false
        )
        
        for file in suggestion.files {
            guard let sourceURL = file.url else { continue }
            
            let sourceCheck = checkFileAccessibility(at: sourceURL)
            if !sourceCheck.accessible, let issue = sourceCheck.issue {
                issues.append(issue)
            }
        }
        
        for subfolder in suggestion.subfolders {
            let subIssues = await preValidateSuggestion(subfolder, parentURL: folderURL)
            issues.append(contentsOf: subIssues)
        }
        
        return issues
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

        _ = try await reverseOperations([lastOperation])
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
    func moveFile(from source: URL, to destination: URL) async throws -> FileOperation {
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

        if isCrossVolume(from: source, to: finalDestination) {
            DebugLogger.log("Cross-volume move detected: \(source.path) → \(finalDestination.path)")
            let fileName = source.lastPathComponent
            let handler = crossVolumeProgressHandler
            try await copyWithProgress(from: source, to: finalDestination) { progress in
                handler?(fileName, progress)
            }
        } else {
            try fileManager.moveItem(at: source, to: finalDestination)
        }

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
        var newURL = url.deletingLastPathComponent().appendingPathComponent(newName)

        // Handle conflicts by generating a unique filename instead of throwing an error
        if fileManager.fileExists(atPath: newURL.path) {
            newURL = generateUniqueURL(for: newURL)
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
                newFilename: newURL.lastPathComponent
            )
        )

        undoStack.append(operation)
        return operation
    }

    /// Delete a file (Now non-destructive: moves to .duplicates)
    func deleteFile(at url: URL, moveToTrash: Bool = true, workspaceURL: URL? = nil) throws -> FileOperation {
        let actualWorkspaceURL = workspaceURL ?? url.deletingLastPathComponent() // Fallback to heuristic
        return try moveToDuplicates(url: url, workspaceURL: actualWorkspaceURL)
    }
    
    /// Non-destructive move to a .duplicates folder
    func moveToDuplicates(url: URL, workspaceURL: URL) throws -> FileOperation {
        let duplicatesDir = workspaceURL.appendingPathComponent(".duplicates")
        
        if !fileManager.fileExists(atPath: duplicatesDir.path) {
            try fileManager.createDirectory(at: duplicatesDir, withIntermediateDirectories: true)
            // Ideally hide this folder?
            // try? (duplicatesDir as NSURL).setResourceValue(true, forKey: .isHiddenKey)
        }
        
        let destinationURL = generateUniqueURL(for: duplicatesDir.appendingPathComponent(url.lastPathComponent))
        
        try fileManager.moveItem(at: url, to: destinationURL)
        
        let operation = FileOperation(
            id: UUID(),
            type: .deleteFile, // Still marked as delete for history logic, but destination is recorded
            sourcePath: url.path,
            destinationPath: destinationURL.path,
            timestamp: Date(),
            metadata: FileOperation.OperationMetadata(
                originalFilename: url.lastPathComponent,
                wasCreatedDuringOrganization: false,
                parentFolderPath: url.deletingLastPathComponent().path
            )
        )
        
        undoStack.append(operation)
        return operation
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
    case fileLocked(String)
    case partialFailure(successCount: Int, failures: [OperationFailure])
    case preValidationFailed([String])
    case crossVolumeCopyVerificationFailed(String)

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
        case .fileLocked(let path):
            return "File is locked or in use: \(path)"
        case .partialFailure(let successCount, let failures):
            return "Partial failure: \(successCount) succeeded, \(failures.count) failed"
        case .preValidationFailed(let issues):
            return "Pre-validation failed: \(issues.joined(separator: ", "))"
        case .crossVolumeCopyVerificationFailed(let path):
            return "Cross-volume copy verification failed for: \(path)"
        }
    }
}

public struct OperationFailure: Sendable {
    public let sourcePath: String
    public let destinationPath: String?
    public let error: String
    public let isRetryable: Bool
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
        
        // Use the original file's location as a base for the .duplicates folder
        let originalURL = URL(fileURLWithPath: originalFile.path)
        let workspaceURL = originalURL.deletingLastPathComponent()
        let duplicatesDir = workspaceURL.appendingPathComponent(".duplicates")
        
        if !fileManager.fileExists(atPath: duplicatesDir.path) {
            try fileManager.createDirectory(at: duplicatesDir, withIntermediateDirectories: true)
        }
        
        for file in filesToDelete {
            // Capture metadata before move
            let attributes = try? fileManager.attributesOfItem(atPath: file.path)
            let metadata = RestorableDuplicate.FileMetadata(
                creationDate: attributes?[.creationDate] as? Date,
                modificationDate: attributes?[.modificationDate] as? Date,
                permissions: attributes?[.posixPermissions] as? Int,
                ownerAccountID: attributes?[.ownerAccountID] as? Int,
                groupOwnerAccountID: attributes?[.groupOwnerAccountID] as? Int
            )
            
            let fileName = URL(fileURLWithPath: file.path).lastPathComponent
            let destinationURL = generateUniqueURL(for: duplicatesDir.appendingPathComponent(fileName))
            
            let item = RestorableDuplicate(
                originalPath: originalFile.path,
                deletedPath: file.path, // Store the ORIGINAL path here
                metadata: metadata
            )
            
            // Perform non-destructive move instead of deletion
            try fileManager.moveItem(atPath: file.path, toPath: destinationURL.path)
            
            // We need to store the backup path somewhere. Since RestorableDuplicate doesn't have a backupPath field,
            // we'll rely on the fact that if we want to restore, we can either copy from originalFile.path 
            // OR move it back from the .duplicates folder if we can find it.
            // For now, let's keep it simple: restoration will copy from the current original.
            
            deletedItems.append(item)
        }
        
        restoredItems.append(contentsOf: deletedItems)
        saveHistory()
        
        return deletedItems
    }
    
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
