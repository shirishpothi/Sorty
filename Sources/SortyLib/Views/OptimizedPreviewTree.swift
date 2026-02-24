//
//  OptimizedPreviewTree.swift
//  Sorty
//
//  Optimized flat-list rendering for large organization previews.
//  Uses a flattened data structure to avoid recursive view creation
//  and improve scrolling performance.
//

import SwiftUI
import UniformTypeIdentifiers
import Combine
import AppKit

// MARK: - Flattened Row Model

struct FlattenedRow: Identifiable, Equatable {
    let id: String
    let depth: Int
    let type: RowType
    let isExpanded: Bool
    
    enum RowType: Equatable {
        case folder(FolderSuggestion)
        case file(FileItem, parentFolderID: UUID)
        case unorganizedHeader
        case unorganizedFile(FileItem)
    }
    
    static func == (lhs: FlattenedRow, rhs: FlattenedRow) -> Bool {
        lhs.id == rhs.id && lhs.depth == rhs.depth && lhs.isExpanded == rhs.isExpanded && lhs.type == rhs.type
    }
}

struct RenameValidationResult: Sendable, Equatable {
    let inputName: String
    let sanitizedName: String?
    let errors: [String]
    let warnings: [String]
    let hasInvalidCharacters: Bool
    let exceedsRecommendedLength: Bool
    let hasConflict: Bool

    var isValid: Bool {
        sanitizedName != nil && errors.isEmpty && !hasConflict
    }
}

struct RenameSummaryEntry: Identifiable, Equatable {
    let id: UUID
    let fileID: UUID
    let folderID: UUID
    let folderName: String
    let originalName: String
    let newName: String
    let reason: String
    let confidence: Double?
    let isLowConfidenceSkip: Bool
}

// MARK: - Preview Store

@MainActor
class PreviewStore: ObservableObject {
    @Published private(set) var flattenedRows: [FlattenedRow] = []
    @Published private(set) var plan: OrganizationPlan
    @Published var expandedFolders: Set<String> = []
    @Published var highlightedFileID: UUID? = nil
    
    /// Pre-computed rename mappings to avoid expensive lookups during rendering
    @Published private(set) var renameMappings: [UUID: FileRenameMapping] = [:]
    
    @Published private(set) var tagMappings: [UUID: [String]] = [:]
    @Published private(set) var folderTagMappings: [UUID: [String]] = [:]
    @Published private(set) var folderCommentMappings: [UUID: String] = [:]
    @Published private(set) var fileCommentMappings: [UUID: String] = [:]

    /// Duplicate file mappings - maps file ID to its duplicate info
    @Published private(set) var duplicateMappings: [UUID: DuplicateInfo] = [:]
    @Published private(set) var initialRenameSuggestions: [UUID: FileRenameMapping] = [:]
    
    /// Cached folder counts to avoid recalculation during scrolling
    private var folderCountCache: [UUID: Int] = [:]
    private var folderCountCacheValid = false
    
    /// Throttled file count display to prevent excessive UI updates
    @Published private(set) var throttledTotalFileCount: Int = 0
    
    private var folderIDToPath: [UUID: String] = [:]
    private var knownFolderIDs: Set<String> = []
    
    /// Plan version tracking for cache invalidation
    private var cachedPlanVersion: Int = -1
    
    /// Throttling support
    private var throttleWorkItem: DispatchWorkItem?
    private let throttleInterval: TimeInterval = 0.2 // 200ms
    
    /// Weak reference to drag drop manager for cache coordination
    weak var dragDropManager: DragDropManager?
    
    init(plan: OrganizationPlan) {
        self.plan = plan
        captureInitialRenameSuggestions(from: plan)
        expandAllFolders()
        rebuildFlattenedRows()
        cachedPlanVersion = plan.version
        throttledTotalFileCount = plan.totalFiles
    }
    
    func updatePlan(_ newPlan: OrganizationPlan) {
        // Only invalidate caches if plan actually changed (by version or content)
        let previousPlanID = plan.id
        let planChanged = newPlan.version != cachedPlanVersion || newPlan.id != plan.id
        self.plan = newPlan
        
        if planChanged {
            if newPlan.id != previousPlanID {
                captureInitialRenameSuggestions(from: newPlan)
            }
            refreshExpandedFolders(for: newPlan)
            // Clear caches when plan changes
            folderCountCache.removeAll()
            folderCountCacheValid = false
            // Update throttled count with debounce
            updateThrottledFileCount()
            // Clear drag drop manager cache
            dragDropManager?.clearDropTargetCache()
        }
        
        rebuildFlattenedRows()
        cachedPlanVersion = newPlan.version
    }

    private func captureInitialRenameSuggestions(from plan: OrganizationPlan) {
        var captured: [UUID: FileRenameMapping] = [:]

        func walk(_ folder: FolderSuggestion) {
            for mapping in folder.fileRenameMappings {
                captured[mapping.originalFile.id] = mapping
            }
            for subfolder in folder.subfolders {
                walk(subfolder)
            }
        }

        for suggestion in plan.suggestions {
            walk(suggestion)
        }

        initialRenameSuggestions = captured
    }
    
    /// Get cached file count for a folder (avoids recalculation during scrolling)
    func getCachedFileCount(for folderID: UUID, compute: () -> Int) -> Int {
        if folderCountCacheValid, let cached = folderCountCache[folderID] {
            return cached
        }
        let count = compute()
        folderCountCache[folderID] = count
        folderCountCacheValid = true
        return count
    }
    
    /// Update file count with throttling to prevent excessive UI updates
    private func updateThrottledFileCount() {
        // Cancel any pending update
        throttleWorkItem?.cancel()
        
        // Create new work item
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            self.throttledTotalFileCount = self.plan.totalFiles
        }
        
        throttleWorkItem = workItem
        
        // Schedule update after throttle interval
        DispatchQueue.main.asyncAfter(deadline: .now() + throttleInterval, execute: workItem)
        
        // Immediately update for the first change or if significant
        if throttledTotalFileCount == 0 || abs(plan.totalFiles - throttledTotalFileCount) > 100 {
            throttledTotalFileCount = plan.totalFiles
            workItem.cancel()
        }
    }
    
    private func expandAllFolders() {
        let ids = collectFolderIDs(from: plan)
        expandedFolders = ids
        knownFolderIDs = ids
    }

    private func refreshExpandedFolders(for plan: OrganizationPlan) {
        let currentIDs = collectFolderIDs(from: plan)
        let newIDs = currentIDs.subtracting(knownFolderIDs)
        expandedFolders = expandedFolders.intersection(currentIDs)
        expandedFolders.formUnion(newIDs)
        knownFolderIDs = currentIDs
    }

    private func collectFolderIDs(from plan: OrganizationPlan) -> Set<String> {
        var ids = Set<String>()
        func traverse(_ folder: FolderSuggestion) {
            ids.insert(folder.id.uuidString)
            for sub in folder.subfolders {
                traverse(sub)
            }
        }
        for suggestion in plan.suggestions {
            traverse(suggestion)
        }
        return ids
    }
    
    private var lastExpandedFolders: Set<String> = []
    private var lastPlanID: UUID?
    
    private func rebuildFlattenedRows() {
        let planChanged = cachedPlanVersion != plan.version || lastPlanID != plan.id

        if !planChanged && expandedFolders == lastExpandedFolders {
            return
        }
        lastPlanID = plan.id
        lastExpandedFolders = expandedFolders

        var rows: [FlattenedRow] = []

        // Always recompute rename mappings when plan version changes
        var mappings: [UUID: FileRenameMapping] = [:]

        func cacheMappings(for folder: FolderSuggestion) {
            for file in folder.files {
                if let mapping = folder.renameMapping(for: file) {
                    mappings[file.id] = mapping
                }
            }
            for subfolder in folder.subfolders {
                cacheMappings(for: subfolder)
            }
        }

        for suggestion in plan.suggestions {
            cacheMappings(for: suggestion)
        }

        var tagsByFileID: [UUID: [String]] = [:]
        var tagsByFolderID: [UUID: [String]] = [:]
        var commentsByFolderID: [UUID: String] = [:]
        var commentsByFileID: [UUID: String] = [:]

        func cacheTagMappings(for folder: FolderSuggestion) {
            for m in folder.fileTagMappings {
                tagsByFileID[m.originalFile.id] = m.tags
                if let comment = m.comment, !comment.isEmpty {
                    commentsByFileID[m.originalFile.id] = comment
                }
            }
            for sub in folder.subfolders { cacheTagMappings(for: sub) }
        }

        func cacheFolderMetadata(for folder: FolderSuggestion) {
            if !folder.tags.isEmpty {
                tagsByFolderID[folder.id] = folder.tags
            }
            if let comment = folder.comment, !comment.isEmpty {
                commentsByFolderID[folder.id] = comment
            }
            for sub in folder.subfolders { cacheFolderMetadata(for: sub) }
        }

        for suggestion in plan.suggestions {
            cacheTagMappings(for: suggestion)
            cacheFolderMetadata(for: suggestion)
        }
        
        func processFolder(_ folder: FolderSuggestion, depth: Int) {
            let id = folder.id.uuidString
            let isExpanded = expandedFolders.contains(id)
            
            rows.append(FlattenedRow(
                id: id,
                depth: depth,
                type: .folder(folder),
                isExpanded: isExpanded
            ))
            
            if isExpanded {
                // Add subfolders
                for subfolder in folder.subfolders {
                    processFolder(subfolder, depth: depth + 1)
                }
                
                // Add files
                for (index, file) in folder.files.enumerated() {
                    rows.append(FlattenedRow(
                        id: "\(folder.id.uuidString)-\(file.id.uuidString)-\(index)",
                        depth: depth + 1,
                        type: .file(file, parentFolderID: folder.id),
                        isExpanded: false
                    ))
                }
            }
        }
        
        for suggestion in plan.suggestions {
            processFolder(suggestion, depth: 0)
        }
        
        if !plan.unorganizedFiles.isEmpty {
            rows.append(FlattenedRow(
                id: "unorganized-header",
                depth: 0,
                type: .unorganizedHeader,
                isExpanded: true
            ))

            for (index, file) in plan.unorganizedFiles.enumerated() {
                rows.append(FlattenedRow(
                    id: "unorganized-\(file.id.uuidString)-\(index)",
                    depth: 1,
                    type: .unorganizedFile(file),
                    isExpanded: false
                ))
            }
        }

        // Compute duplicate mappings based on file hashes
        let duplicatesByFileID = computeDuplicateMappings()

        self.renameMappings = mappings
        self.tagMappings = tagsByFileID
        self.folderTagMappings = tagsByFolderID
        self.folderCommentMappings = commentsByFolderID
        self.fileCommentMappings = commentsByFileID
        self.duplicateMappings = duplicatesByFileID
        self.flattenedRows = rows
    }

    /// Computes duplicate mappings by grouping files with the same hash
    private func computeDuplicateMappings() -> [UUID: DuplicateInfo] {
        var allFiles: [FileItem] = []

        // Collect all files from suggestions
        func collectFiles(from folder: FolderSuggestion) {
            allFiles.append(contentsOf: folder.files)
            for subfolder in folder.subfolders {
                collectFiles(from: subfolder)
            }
        }

        for suggestion in plan.suggestions {
            collectFiles(from: suggestion)
        }

        // Also include unorganized files
        allFiles.append(contentsOf: plan.unorganizedFiles)

        // Group by hash (only files that have a hash)
        var hashGroups: [String: [FileItem]] = [:]
        for file in allFiles {
            guard let hash = file.sha256Hash, !hash.isEmpty else { continue }
            hashGroups[hash, default: []].append(file)
        }

        // Create duplicate info for files that have duplicates
        var duplicateInfo: [UUID: DuplicateInfo] = [:]
        for (_, files) in hashGroups where files.count > 1 {
            for file in files {
                let others = files.filter { $0.id != file.id }
                duplicateInfo[file.id] = DuplicateInfo(
                    file: file,
                    duplicates: others,
                    isExactMatch: true,
                    similarity: 1.0
                )
            }
        }

        return duplicateInfo
    }

    private func buildChildRows(for folder: FolderSuggestion, depth: Int) -> [FlattenedRow] {
        var rows: [FlattenedRow] = []

        for subfolder in folder.subfolders {
            let id = subfolder.id.uuidString
            let isExpanded = expandedFolders.contains(id)

            rows.append(FlattenedRow(
                id: id,
                depth: depth,
                type: .folder(subfolder),
                isExpanded: isExpanded
            ))

            if isExpanded {
                rows.append(contentsOf: buildChildRows(for: subfolder, depth: depth + 1))
            }
        }

        for (index, file) in folder.files.enumerated() {
            rows.append(FlattenedRow(
                id: "\(folder.id.uuidString)-\(file.id.uuidString)-\(index)",
                depth: depth,
                type: .file(file, parentFolderID: folder.id),
                isExpanded: false
            ))
        }

        return rows
    }

    private func applyIncrementalToggle(id: String, wasExpanded: Bool) -> Bool {
        guard let rowIndex = flattenedRows.firstIndex(where: { $0.id == id }) else { return false }
        guard case .folder(let folder) = flattenedRows[rowIndex].type else { return false }

        let depth = flattenedRows[rowIndex].depth

        if wasExpanded {
            var removalIndex = rowIndex + 1
            while removalIndex < flattenedRows.count, flattenedRows[removalIndex].depth > depth {
                removalIndex += 1
            }
            if removalIndex > rowIndex + 1 {
                flattenedRows.removeSubrange((rowIndex + 1)..<removalIndex)
            }
            flattenedRows[rowIndex] = FlattenedRow(
                id: id,
                depth: depth,
                type: .folder(folder),
                isExpanded: false
            )
            return true
        } else {
            let childRows = buildChildRows(for: folder, depth: depth + 1)
            flattenedRows[rowIndex] = FlattenedRow(
                id: id,
                depth: depth,
                type: .folder(folder),
                isExpanded: true
            )
            if !childRows.isEmpty {
                flattenedRows.insert(contentsOf: childRows, at: rowIndex + 1)
            }
            return true
        }
    }
    
    func toggleFolder(id: String) {
        let wasExpanded = expandedFolders.contains(id)
        if wasExpanded {
            expandedFolders.remove(id)
        } else {
            expandedFolders.insert(id)
        }

        if cachedPlanVersion == plan.version, applyIncrementalToggle(id: id, wasExpanded: wasExpanded) {
            lastExpandedFolders = expandedFolders
        } else {
            rebuildFlattenedRows()
        }
    }

    func revealFileAndResolveRowID(_ fileID: UUID) -> String? {
        var didExpandAnyFolder = false

        if let folderPath = folderPathForFile(fileID: fileID) {
            for folderID in folderPath {
                let folderRowID = folderID.uuidString
                if !expandedFolders.contains(folderRowID) {
                    expandedFolders.insert(folderRowID)
                    didExpandAnyFolder = true
                }
            }
        }

        if didExpandAnyFolder {
            rebuildFlattenedRows()
        }

        return flattenedRows.first { row in
            switch row.type {
            case .file(let file, _):
                return file.id == fileID
            case .unorganizedFile(let file):
                return file.id == fileID
            case .folder, .unorganizedHeader:
                return false
            }
        }?.id
    }

    func folderSuggestion(for folderID: UUID) -> FolderSuggestion? {
        for suggestion in plan.suggestions {
            if let matched = folderSuggestion(for: folderID, in: suggestion) {
                return matched
            }
        }
        return nil
    }
    
    func moveFileToUnorganized(fileID: UUID) {
        guard let file = findFile(by: fileID) else { return }
        
        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[i] = removeFileFromFolder(file, from: updatedPlan.suggestions[i])
        }
        
        if !updatedPlan.unorganizedFiles.contains(where: { $0.id == fileID }) {
            updatedPlan.unorganizedFiles.append(file)
        }
        
        updateInternalPlan(updatedPlan)
    }
    
    @discardableResult
    func updateRename(fileID: UUID, folderID: UUID, newName: String) -> Bool {
        let validation = renameValidation(for: fileID, folderID: folderID, proposedName: newName)
        guard validation.isValid, let safeName = validation.sanitizedName else {
            return false
        }

        if let originalFile = findFile(by: fileID), safeName == originalFile.displayName {
            if renameMappings[fileID]?.hasRename == true {
                rejectRename(fileID: fileID, folderID: folderID)
                return true
            }
            return false
        }

        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            if let updated = updateRenameInFolder(updatedPlan.suggestions[i], targetID: folderID, fileID: fileID, newName: safeName) {
                updatedPlan.suggestions[i] = updated
                updateInternalPlan(updatedPlan)
                return true
            }
        }
        return false
    }
    
    func rejectRename(fileID: UUID, folderID: UUID) {
        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            if let updated = rejectRenameInFolder(updatedPlan.suggestions[i], targetID: folderID, fileID: fileID) {
                updatedPlan.suggestions[i] = updated
                updateInternalPlan(updatedPlan)
                return
            }
        }
    }

    func acceptAllRenames() {
        var updatedPlan = plan
        updatedPlan.suggestions = updatedPlan.suggestions.map { acceptRenamesInFolder($0) }
        updateInternalPlan(updatedPlan)
    }

    func rejectAllRenames() {
        var updatedPlan = plan
        updatedPlan.suggestions = updatedPlan.suggestions.map { rejectRenamesInFolder($0) }
        updateInternalPlan(updatedPlan)
    }

    func acceptRenames(in folderID: UUID) {
        var updatedPlan = plan
        for index in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[index] = acceptRenamesInFolder(updatedPlan.suggestions[index], targetID: folderID)
        }
        updateInternalPlan(updatedPlan)
    }

    func rejectRenames(in folderID: UUID) {
        var updatedPlan = plan
        for index in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[index] = rejectRenamesInFolder(updatedPlan.suggestions[index], targetID: folderID)
        }
        updateInternalPlan(updatedPlan)
    }

    func renameValidation(for fileID: UUID, folderID: UUID, proposedName: String) -> RenameValidationResult {
        guard let file = findFile(by: fileID) else {
            return RenameValidationResult(
                inputName: proposedName,
                sanitizedName: nil,
                errors: ["File not found."],
                warnings: [],
                hasInvalidCharacters: false,
                exceedsRecommendedLength: false,
                hasConflict: false
            )
        }

        let sanitization = FilenameSanitizer.sanitize(
            proposedName,
            preservingExtension: file.extension,
            enforceExtension: true
        )

        let conflict = sanitization.sanitizedName.map {
            hasFilenameConflict(in: folderID, candidateName: $0, excluding: fileID)
        } ?? false

        var errors = sanitization.errors
        if conflict {
            errors.append("A file with this name already exists in this folder.")
        }

        return RenameValidationResult(
            inputName: proposedName,
            sanitizedName: sanitization.sanitizedName,
            errors: errors,
            warnings: sanitization.warnings,
            hasInvalidCharacters: sanitization.hadInvalidCharacters,
            exceedsRecommendedLength: sanitization.exceededRecommendedLength,
            hasConflict: conflict
        )
    }

    func renameSummaryEntries() -> [RenameSummaryEntry] {
        var entries: [RenameSummaryEntry] = []

        func walk(_ folder: FolderSuggestion) {
            for file in folder.files {
                guard let mapping = folder.renameMapping(for: file) else { continue }
                let hasRename = mapping.hasRename
                let isSkip = mapping.isAutoSkippedForLowConfidence
                guard hasRename || isSkip else { continue }

                let folderDisplayName = folder.folderName.hasPrefix("/")
                    ? URL(fileURLWithPath: folder.folderName).lastPathComponent
                    : folder.folderName

                entries.append(
                    RenameSummaryEntry(
                        id: file.id,
                        fileID: file.id,
                        folderID: folder.id,
                        folderName: folderDisplayName,
                        originalName: file.displayName,
                        newName: mapping.suggestedName ?? file.displayName,
                        reason: mapping.renameReason ?? (isSkip ? "AI unsure" : "AI suggested rename"),
                        confidence: mapping.renameConfidence,
                        isLowConfidenceSkip: isSkip
                    )
                )
            }

            for subfolder in folder.subfolders {
                walk(subfolder)
            }
        }

        for suggestion in plan.suggestions {
            walk(suggestion)
        }

        return entries
    }
    
    func revertFolderOrganization(folderID: UUID) {
        var updatedPlan = plan
        var filesToMove: [FileItem] = []
        
        func collectFilesFromFolder(_ folder: FolderSuggestion) {
            filesToMove.append(contentsOf: folder.files)
            for subfolder in folder.subfolders {
                collectFilesFromFolder(subfolder)
            }
        }
        
        for i in 0..<updatedPlan.suggestions.count {
            if let folder = findFolderByID(folderID, in: updatedPlan.suggestions[i]) {
                collectFilesFromFolder(folder)
                updatedPlan.suggestions[i] = removeFolderFromSuggestion(updatedPlan.suggestions[i], targetID: folderID)
                break
            }
        }
        
        updatedPlan.suggestions.removeAll { $0.files.isEmpty && $0.subfolders.isEmpty && $0.id == folderID }
        
        for file in filesToMove {
            if !updatedPlan.unorganizedFiles.contains(where: { $0.id == file.id }) {
                updatedPlan.unorganizedFiles.append(file)
            }
        }
        
        updateInternalPlan(updatedPlan)
    }

    func updateFolderDestination(folderID: UUID, newDestinationPath: String) {
        let canonicalPath = StorageLocationPathResolver.canonicalPath(newDestinationPath)
        var updatedPlan = plan

        for i in 0..<updatedPlan.suggestions.count {
            if let updated = updateDestinationInFolder(updatedPlan.suggestions[i], targetID: folderID, newDestinationPath: canonicalPath) {
                updatedPlan.suggestions[i] = updated
                updateInternalPlan(updatedPlan)
                return
            }
        }
    }
    
    private func findFolderByID(_ id: UUID, in folder: FolderSuggestion) -> FolderSuggestion? {
        if folder.id == id { return folder }
        for subfolder in folder.subfolders {
            if let found = findFolderByID(id, in: subfolder) { return found }
        }
        return nil
    }
    
    private func removeFolderFromSuggestion(_ folder: FolderSuggestion, targetID: UUID) -> FolderSuggestion {
        var updatedFolder = folder
        updatedFolder.subfolders.removeAll { $0.id == targetID }
        updatedFolder.subfolders = updatedFolder.subfolders.map { removeFolderFromSuggestion($0, targetID: targetID) }
        return updatedFolder
    }
    
    private func updateRenameInFolder(_ folder: FolderSuggestion, targetID: UUID, fileID: UUID, newName: String) -> FolderSuggestion? {
        var updatedFolder = folder
        if folder.id == targetID {
            if let file = updatedFolder.files.first(where: { $0.id == fileID }) {
                updatedFolder.updateRename(for: file, newName: newName)
                return updatedFolder
            }
        }
        
        for i in 0..<updatedFolder.subfolders.count {
            if let updated = updateRenameInFolder(updatedFolder.subfolders[i], targetID: targetID, fileID: fileID, newName: newName) {
                updatedFolder.subfolders[i] = updated
                return updatedFolder
            }
        }
        return nil
    }

    private func updateDestinationInFolder(_ folder: FolderSuggestion, targetID: UUID, newDestinationPath: String) -> FolderSuggestion? {
        var updatedFolder = folder
        if folder.id == targetID {
            updatedFolder.folderName = newDestinationPath
            return updatedFolder
        }

        for i in 0..<updatedFolder.subfolders.count {
            if let updated = updateDestinationInFolder(updatedFolder.subfolders[i], targetID: targetID, newDestinationPath: newDestinationPath) {
                updatedFolder.subfolders[i] = updated
                return updatedFolder
            }
        }

        return nil
    }
    
    private func rejectRenameInFolder(_ folder: FolderSuggestion, targetID: UUID, fileID: UUID) -> FolderSuggestion? {
        var updatedFolder = folder
        if folder.id == targetID {
            if let file = updatedFolder.files.first(where: { $0.id == fileID }) {
                updatedFolder.updateRename(for: file, newName: nil)
                return updatedFolder
            }
        }
        
        for i in 0..<updatedFolder.subfolders.count {
            if let updated = rejectRenameInFolder(updatedFolder.subfolders[i], targetID: targetID, fileID: fileID) {
                updatedFolder.subfolders[i] = updated
                return updatedFolder
            }
        }
        return nil
    }

    private func acceptRenamesInFolder(_ folder: FolderSuggestion, targetID: UUID? = nil) -> FolderSuggestion {
        var updatedFolder = folder
        let shouldApplyHere = targetID == nil || folder.id == targetID

        if shouldApplyHere {
            for file in updatedFolder.files {
                guard let initial = initialRenameSuggestions[file.id], initial.hasRename, let suggested = initial.suggestedName else {
                    continue
                }
                updatedFolder.updateRename(
                    for: file,
                    newName: suggested,
                    reason: initial.renameReason,
                    confidence: initial.renameConfidence
                )
            }
        }

        updatedFolder.subfolders = updatedFolder.subfolders.map {
            acceptRenamesInFolder($0, targetID: targetID)
        }
        return updatedFolder
    }

    private func rejectRenamesInFolder(_ folder: FolderSuggestion, targetID: UUID? = nil) -> FolderSuggestion {
        var updatedFolder = folder
        let shouldApplyHere = targetID == nil || folder.id == targetID

        if shouldApplyHere {
            for file in updatedFolder.files {
                guard initialRenameSuggestions[file.id] != nil || updatedFolder.renameMapping(for: file)?.hasRename == true else {
                    continue
                }
                updatedFolder.updateRename(for: file, newName: nil)
            }
        }

        updatedFolder.subfolders = updatedFolder.subfolders.map {
            rejectRenamesInFolder($0, targetID: targetID)
        }
        return updatedFolder
    }
    
    private func updateInternalPlan(_ updatedPlan: OrganizationPlan) {
        let finalPlan = OrganizationPlan(
            id: updatedPlan.id,
            suggestions: updatedPlan.suggestions,
            unorganizedFiles: updatedPlan.unorganizedFiles,
            unorganizedDetails: updatedPlan.unorganizedDetails,
            notes: updatedPlan.notes,
            timestamp: Date(),
            version: updatedPlan.version + 1,
            generationStats: updatedPlan.generationStats
        )
        plan = finalPlan
        folderCountCache.removeAll()
        folderCountCacheValid = false
        updateThrottledFileCount()
        dragDropManager?.clearDropTargetCache()
        rebuildFlattenedRows()
        cachedPlanVersion = finalPlan.version
    }
    
    func moveFile(fileID: UUID, toFolderID: UUID) {
        guard let file = findFile(by: fileID) else { return }
        
        var updatedPlan = plan
        
        // Remove from current location
        for i in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[i] = removeFileFromFolder(file, from: updatedPlan.suggestions[i])
        }
        updatedPlan.unorganizedFiles.removeAll { $0.id == fileID }
        
        // Add to new location
        for i in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[i] = addFileToFolder(file, to: updatedPlan.suggestions[i], targetId: toFolderID)
        }
        
        updateInternalPlan(updatedPlan)
    }
    
    private func findFile(by id: UUID) -> FileItem? {
        for suggestion in plan.suggestions {
            if let file = findFileInFolder(id, in: suggestion) {
                return file
            }
        }
        return plan.unorganizedFiles.first { $0.id == id }
    }
    
    private func findFileInFolder(_ id: UUID, in folder: FolderSuggestion) -> FileItem? {
        if let file = folder.files.first(where: { $0.id == id }) {
            return file
        }
        for subfolder in folder.subfolders {
            if let file = findFileInFolder(id, in: subfolder) {
                return file
            }
        }
        return nil
    }

    private func folderPathForFile(fileID: UUID) -> [UUID]? {
        for suggestion in plan.suggestions {
            if let path = folderPathForFile(fileID: fileID, in: suggestion, ancestors: []) {
                return path
            }
        }
        return nil
    }

    private func folderPathForFile(fileID: UUID, in folder: FolderSuggestion, ancestors: [UUID]) -> [UUID]? {
        let nextAncestors = ancestors + [folder.id]
        if folder.files.contains(where: { $0.id == fileID }) {
            return nextAncestors
        }

        for subfolder in folder.subfolders {
            if let found = folderPathForFile(fileID: fileID, in: subfolder, ancestors: nextAncestors) {
                return found
            }
        }

        return nil
    }

    private func folderSuggestion(for folderID: UUID, in folder: FolderSuggestion) -> FolderSuggestion? {
        if folder.id == folderID {
            return folder
        }
        for subfolder in folder.subfolders {
            if let matched = folderSuggestion(for: folderID, in: subfolder) {
                return matched
            }
        }
        return nil
    }
    
    private func removeFileFromFolder(_ file: FileItem, from folder: FolderSuggestion) -> FolderSuggestion {
        var updatedFolder = folder
        updatedFolder.files.removeAll { $0.id == file.id }
        updatedFolder.subfolders = updatedFolder.subfolders.map { subfolder in
            removeFileFromFolder(file, from: subfolder)
        }
        return updatedFolder
    }
    
    private func addFileToFolder(_ file: FileItem, to folder: FolderSuggestion, targetId: UUID) -> FolderSuggestion {
        var updatedFolder = folder
        
        if folder.id == targetId {
            if !updatedFolder.files.contains(where: { $0.id == file.id }) {
                updatedFolder.files.append(file)
            }
        } else {
            updatedFolder.subfolders = updatedFolder.subfolders.map { subfolder in
                addFileToFolder(file, to: subfolder, targetId: targetId)
            }
        }
        
        return updatedFolder
    }

    private func hasFilenameConflict(in folderID: UUID, candidateName: String, excluding fileID: UUID) -> Bool {
        guard let folder = folderSuggestion(for: folderID) else { return false }

        let normalizedCandidate = candidateName.lowercased()
        for file in folder.files where file.id != fileID {
            let existingName = folder.renameMapping(for: file)?.suggestedName ?? file.displayName
            if existingName.lowercased() == normalizedCandidate {
                return true
            }
        }
        return false
    }
}

// MARK: - Optimized Preview Tree View

struct OptimizedPreviewTree: View {
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    var onFocusInstructions: (() -> Void)? = nil
    var enableManualRenameTools: Bool = false
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.flattenedRows, id: \.id) { row in
                        FlattenedRowView(
                            row: row,
                            store: store,
                            dragDropManager: dragDropManager,
                            onPlanChanged: onPlanChanged,
                            onFocusInstructions: onFocusInstructions,
                            enableManualRenameTools: enableManualRenameTools
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .onChange(of: store.highlightedFileID) { _, highlightedFileID in
                guard let highlightedFileID else { return }
                guard let rowID = store.revealFileAndResolveRowID(highlightedFileID) else { return }
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    scrollProxy.scrollTo(rowID, anchor: .center)
                }
            }
        }
    }

    private func findFolderByID(_ id: UUID, in folder: FolderSuggestion) -> FolderSuggestion? {
        if folder.id == id { return folder }
        for sub in folder.subfolders {
            if let found = findFolderByID(id, in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Flattened Row View

struct FlattenedRowView: View {
    let row: FlattenedRow
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    var onFocusInstructions: (() -> Void)? = nil
    var enableManualRenameTools: Bool = false
    
    var body: some View {
        switch row.type {
        case .folder(let suggestion):
            FlatFolderRowView(
                suggestion: suggestion,
                depth: row.depth,
                isExpanded: row.isExpanded,
                rowID: row.id,
                store: store,
                dragDropManager: dragDropManager,
                onPlanChanged: onPlanChanged
            )
        case .file(let file, let parentFolderID):
            FlatFileRowView(
                file: file,
                depth: row.depth,
                parentFolderID: parentFolderID,
                store: store,
                dragDropManager: dragDropManager,
                onPlanChanged: onPlanChanged,
                onFocusInstructions: onFocusInstructions,
                enableManualRenameTools: enableManualRenameTools
            )
        case .unorganizedHeader:
            FlatUnorganizedHeaderView(
                fileCount: store.plan.unorganizedFiles.count,
                store: store,
                dragDropManager: dragDropManager,
                onPlanChanged: onPlanChanged
            )
        case .unorganizedFile(let file):
            FlatUnorganizedFileRowView(
                file: file,
                dragDropManager: dragDropManager,
                store: store
            )
        }
    }
}

// MARK: - Flat Folder Row View

struct FlatFolderRowView: View {
    let suggestion: FolderSuggestion
    let depth: Int
    let isExpanded: Bool
    let rowID: String
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    @EnvironmentObject var learningsManager: LearningsManager
    @EnvironmentObject var storageLocationsManager: StorageLocationsManager
    
    @State private var isDropTarget = false
    @State private var showStorageLocationPicker = false
    @State private var storageLocationPickerErrorMessage: String?

    private var folderTags: [String] {
        store.folderTagMappings[suggestion.id] ?? []
    }

    private var folderComment: String? {
        store.folderCommentMappings[suggestion.id]
    }

    private var isStorageDestination: Bool {
        suggestion.folderName.hasPrefix("/")
    }

    private var matchedStorageLocation: StorageLocation? {
        guard isStorageDestination else { return nil }
        return storageLocationsManager.locations
            .filter { StorageLocationPathResolver.isPath(suggestion.folderName, within: $0.path) }
            .sorted { $0.path.count > $1.path.count }
            .first
    }

    private var usedStorageURL: URL? {
        if let matchedStorageLocation {
            return URL(fileURLWithPath: matchedStorageLocation.path, isDirectory: true)
        }
        return StorageLocationPathResolver.absoluteURL(from: suggestion.folderName)
    }

    private var usedStorageDisplayName: String {
        if let matchedStorageLocation {
            return matchedStorageLocation.name
        }
        return usedStorageURL?.lastPathComponent ?? "Storage"
    }

    private var usedStoragePath: String {
        if let matchedStorageLocation {
            return matchedStorageLocation.path
        }
        return usedStorageURL?.path ?? suggestion.folderName
    }

    private var folderRenameCount: Int {
        suggestion.allFileRenameMappings.filter { $0.hasRename }.count
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 20)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .animation(.spring(response: 0.25, dampingFraction: 0.75), value: isExpanded)
                
                CompactFolderThumbnail(
                    url: nil,
                    folderName: suggestion.folderName,
                    size: 16,
                    fileCount: store.getCachedFileCount(for: suggestion.id) { suggestion.totalFileCount }
                )
                .opacity(isDropTarget ? 0.7 : 1.0)
                
                Text(suggestion.folderName.hasPrefix("/") ? URL(fileURLWithPath: suggestion.folderName).lastPathComponent : suggestion.folderName)
                    .fontWeight(.medium)
                
                Text("(\(store.getCachedFileCount(for: suggestion.id) { suggestion.totalFileCount }) files)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if isStorageDestination {
                    storageLocationDropdown
                }

                if !folderTags.isEmpty {
                    TagDotsView(tags: folderTags)
                }

                if let comment = folderComment, !comment.isEmpty {
                    CommentBubbleButton(comment: comment)
                }
                
                Spacer()
                
                LiquidGlassReasoningButton(
                    suggestion: suggestion,
                    learningsManager: learningsManager
                )
            }
            .padding(.leading, CGFloat(depth * 16))
            .padding(.vertical, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    store.toggleFolder(id: rowID)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isDropTarget ? Color.accentColor.opacity(0.1) : Color.clear)
                    .strokeBorder(isDropTarget ? Color.accentColor.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .contextMenu {
                if folderRenameCount > 0 {
                    Button {
                        store.acceptRenames(in: suggestion.id)
                        onPlanChanged()
                    } label: {
                        Label("Accept Renames in Folder", systemImage: "checkmark.circle")
                    }

                    Button {
                        store.rejectRenames(in: suggestion.id)
                        onPlanChanged()
                    } label: {
                        Label("Reject Renames in Folder", systemImage: "xmark.circle")
                    }

                    Divider()
                }

                Button(role: .destructive) {
                    store.revertFolderOrganization(folderID: suggestion.id)
                    onPlanChanged()
                } label: {
                    Label("Revert Organization", systemImage: "arrow.uturn.backward")
                }

                if isStorageDestination {
                    Divider()

                    Button("Change Storage Location…") {
                        showStorageLocationPicker = true
                    }

                    Button("Show in Finder") {
                        revealStorageLocationInFinder()
                    }
                }
            }
            .onDrop(of: [.text], delegate: OptimizedFileDropDelegate(
                targetFolderID: suggestion.id,
                store: store,
                draggedFile: $dragDropManager.draggedFile,
                isTargeted: $isDropTarget,
                onPlanChanged: onPlanChanged
            ))
            .fileImporter(
                isPresented: $showStorageLocationPicker,
                allowedContentTypes: [.folder],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let selectedURL = urls.first else { return }
                    do {
                        try storageLocationsManager.addLocation(url: selectedURL, customName: nil)
                    } catch {
                        DebugLogger.log("Could not add selected storage location during preview destination change: \(error)")
                    }
                    store.updateFolderDestination(folderID: suggestion.id, newDestinationPath: selectedURL.path)
                    onPlanChanged()
                case .failure(let error):
                    storageLocationPickerErrorMessage = error.localizedDescription
                }
            }
            .alert(
                "Couldn’t Change Storage Location",
                isPresented: Binding(
                    get: { storageLocationPickerErrorMessage != nil },
                    set: { isPresented in
                        if !isPresented {
                            storageLocationPickerErrorMessage = nil
                        }
                    }
                )
            ) {
                Button("OK", role: .cancel) {
                    storageLocationPickerErrorMessage = nil
                }
            } message: {
                Text(storageLocationPickerErrorMessage ?? "Please try selecting the folder again.")
            }
        }
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
    }

    private var storageLocationDropdown: some View {
        Menu {
            Button {
            } label: {
                HStack(spacing: 8) {
                    finderIcon(for: usedStoragePath)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(usedStorageDisplayName)
                            .font(.caption)
                        Text(usedStoragePath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .disabled(true)

            Divider()

            Button("Change Storage Location…") {
                showStorageLocationPicker = true
            }

            Button("Show in Finder") {
                revealStorageLocationInFinder()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.3),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                Image(systemName: "externaldrive")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Storage location: \(usedStorageDisplayName)")
    }

    private func finderIcon(for path: String) -> some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .interpolation(.high)
            .frame(width: 12, height: 12)
            .clipShape(RoundedRectangle(cornerRadius: 2))
    }

    private func revealStorageLocationInFinder() {
        guard let usedStorageURL else { return }
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: usedStorageURL.path)
    }
}

// MARK: - Flat File Row View

struct FlatFileRowView: View {
    let file: FileItem
    let depth: Int
    let parentFolderID: UUID
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    var onFocusInstructions: (() -> Void)? = nil
    var enableManualRenameTools: Bool = false
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var learningsManager: LearningsManager
    @EnvironmentObject var organizer: FolderOrganizer
    
    @State private var isDragging = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var showRenamePopover = false
    @State private var showManualRenamePopover = false
    @State private var steeringInstructionDraft = ""
    @FocusState private var isFocused: Bool
    
    private var renameMapping: FileRenameMapping? {
        store.renameMappings[file.id]
    }

    private var fileTags: [String] {
        // Filter out "Duplicate" tag since we show it via LiquidGlassDuplicateButton
        let tags = store.tagMappings[file.id] ?? []
        return tags.filter { $0.lowercased() != "duplicate" }
    }

    private var fileComment: String? {
        store.fileCommentMappings[file.id]
    }

    private var duplicateInfo: DuplicateInfo? {
        store.duplicateMappings[file.id]
    }

    private var parentSuggestion: FolderSuggestion? {
        store.folderSuggestion(for: parentFolderID)
    }
    
    private var isHighlighted: Bool {
        store.highlightedFileID == file.id
    }

    private var renameValidation: RenameValidationResult {
        store.renameValidation(for: file.id, folderID: parentFolderID, proposedName: editedName)
    }

    private var activeFilenameForEditing: String {
        renameMapping?.suggestedName ?? file.displayName
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                FileThumbnailView(url: URL(fileURLWithPath: file.path), size: CGSize(width: 20, height: 20))
                
                if isEditingName {
                    TextField("New name", text: $editedName)
                        .textFieldStyle(.plain)
                        .focused($isFocused)
                        .onSubmit {
                            saveRename()
                        }
                        .onExitCommand {
                            cancelRename()
                        }
                        .font(.body)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(.thinMaterial)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(renameFieldBorderColor, lineWidth: 1)
                                )
                        )
                } else {
                    Text(file.displayName)
                        .lineLimit(1)
                        .strikethrough(renameMapping?.hasRename ?? false, color: .secondary)
                        .foregroundColor((renameMapping?.hasRename ?? false) ? .secondary : .primary)
                }
                
                Spacer()
                
                if let mapping = renameMapping, mapping.hasRename || mapping.isAutoSkippedForLowConfidence {
                    Button {
                        showRenamePopover.toggle()
                    } label: {
                        Image(systemName: "sparkles")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(mapping.isLowConfidence ? Color.orange : Color.accentColor)
                            .padding(6)
                            .background(
                                Circle()
                                    .fill(.ultraThinMaterial)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white.opacity(0.25), lineWidth: 0.8)
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("PreviewRenameInsightButton-\(file.id.uuidString)")
                    .help("View rename reason")
                    .popover(isPresented: $showRenamePopover) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rename Insight")
                                .font(.caption)
                                .fontWeight(.semibold)

                            Text(mapping.renameReason ?? "AI suggested rename")
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)

                            if let confidence = mapping.renameConfidence {
                                Text("Confidence: \(Int(confidence * 100))%")
                                    .font(.caption)
                                    .foregroundStyle(confidence < FileRenameMapping.lowConfidenceThreshold ? .orange : .secondary)
                            }
                        }
                        .padding(12)
                        .frame(minWidth: 220, maxWidth: 320)
                    }
                }

                if enableManualRenameTools {
                    manualRenameControl
                }

                if !fileTags.isEmpty {
                    TagDotsView(tags: fileTags)
                }

                if let comment = fileComment, !comment.isEmpty {
                    CommentBubbleButton(comment: comment)
                }

                if let parentSuggestion {
                    LiquidGlassLearningsButton(
                        file: file,
                        suggestion: parentSuggestion,
                        learningsManager: learningsManager
                    )
                }

                if let dupInfo = duplicateInfo {
                    LiquidGlassDuplicateButton(
                        duplicateInfo: dupInfo,
                        handoffDirectory: appState.selectedDirectory,
                        highlightedFileID: $store.highlightedFileID
                    )
                }

                Text(file.formattedSize)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                
                Image(systemName: "line.3.horizontal")
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.6))
            }
            
            if let mapping = renameMapping, !isEditingName {
                if mapping.hasRename {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.right")
                            .font(.caption2)
                            .foregroundStyle(Color.accentColor)
                        
                        Text(mapping.suggestedName ?? "")
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(Color.accentColor)
                            .lineLimit(1)
                        
                        Spacer()
                        
                        Button {
                            startEditing(initialValue: mapping.suggestedName ?? "")
                        } label: {
                            Image(systemName: "pencil")
                                .font(.caption2)
                                .foregroundStyle(Color.accentColor)
                                .padding(4)
                                .background(Circle().fill(Color.accentColor.opacity(0.12)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("PreviewRenameEditButton-\(file.id.uuidString)")
                        .help("Edit suggested name")
                        
                        Button {
                            store.rejectRename(fileID: file.id, folderID: parentFolderID)
                            onPlanChanged()
                        } label: {
                            Image(systemName: "xmark.circle")
                                .font(.caption2)
                                .foregroundStyle(.red.opacity(0.85))
                                .padding(4)
                                .background(Circle().fill(Color.red.opacity(0.1)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("PreviewRenameRejectButton-\(file.id.uuidString)")
                        .help("Keep original name")
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(0.22), lineWidth: 0.8)
                            )
                    )
                    .padding(.leading, 20)
                } else if mapping.isAutoSkippedForLowConfidence {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("AI unsure - kept original name")
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding(.leading, 20)
                }
            }

            if isEditingName && (!renameValidation.errors.isEmpty || !renameValidation.warnings.isEmpty || renameValidation.hasConflict) {
                Text(renameValidationMessage)
                    .font(.caption2)
                    .foregroundStyle(renameValidation.errors.isEmpty && !renameValidation.hasConflict ? .orange : .red)
                    .padding(.leading, 20)
            }
        }
        .padding(.leading, CGFloat(depth * 16))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : (isDragging ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.accentColor.opacity(0.3) : (isEditingName ? Color.accentColor.opacity(0.3) : Color.clear), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Button {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
            
            Divider()
            
            if let mapping = renameMapping, mapping.hasRename {
                Button(role: .destructive) {
                    store.rejectRename(fileID: file.id, folderID: parentFolderID)
                    onPlanChanged()
                } label: {
                    Label("Revert Name", systemImage: "arrow.uturn.backward")
                }
            }
            
            Button(role: .destructive) {
                store.moveFileToUnorganized(fileID: file.id)
                onPlanChanged()
            } label: {
                Label("Revert Organization", systemImage: "questionmark.folder")
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag {
            isDragging = true
            dragDropManager.startDrag(file)
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
        .onDrop(of: [.text], isTargeted: nil) { _ in
            isDragging = false
            return false
        }
        .onDisappear {
            isDragging = false
            isEditingName = false
        }
    }
    
    private func fileIcon(for file: FileItem) -> String {
        switch file.extension.lowercased() {
        case "pdf": return "doc.richtext"
        case "jpg", "jpeg", "png", "heic": return "photo"
        case "mp4", "mov": return "video"
        case "mp3", "wav", "aac", "m4a", "flac", "ogg": return "waveform"
        case "zip", "gz", "rar": return "archivebox"
        case "dmg", "iso": return "externaldrive"
        case "pkg", "app": return "shippingbox"
        case "swift", "js", "py", "ts": return "doc.text.fill"
        default: return "doc"
        }
    }

    private var renameFieldBorderColor: Color {
        if renameValidation.hasConflict || !renameValidation.errors.isEmpty || renameValidation.hasInvalidCharacters {
            return .red.opacity(0.8)
        }
        if renameValidation.exceedsRecommendedLength || !renameValidation.warnings.isEmpty {
            return .orange.opacity(0.8)
        }
        return .accentColor.opacity(0.45)
    }

    private var renameValidationMessage: String {
        if renameValidation.hasConflict {
            return "Name conflicts with another file in this folder."
        }
        if let firstError = renameValidation.errors.first {
            return firstError
        }
        if renameValidation.hasInvalidCharacters {
            return "Contains invalid macOS filename characters."
        }
        if renameValidation.exceedsRecommendedLength {
            return "Name exceeds the recommended 60 characters."
        }
        if let firstWarning = renameValidation.warnings.first {
            return firstWarning
        }
        return ""
    }
    
    private func startEditing(initialValue: String) {
        editedName = initialValue
        isEditingName = true
        isFocused = true
    }
    
    private func saveRename() {
        let validation = renameValidation
        guard validation.isValid, let sanitizedName = validation.sanitizedName else {
            HapticFeedbackManager.shared.error()
            return
        }

        if sanitizedName == file.displayName {
            if renameMapping?.hasRename == true {
                store.rejectRename(fileID: file.id, folderID: parentFolderID)
                onPlanChanged()
            }
            isEditingName = false
            return
        }

        if !sanitizedName.isEmpty {
            if store.updateRename(fileID: file.id, folderID: parentFolderID, newName: sanitizedName) {
                onPlanChanged()
            }
        }
        isEditingName = false
    }
    
    private func cancelRename() {
        isEditingName = false
    }

    private var manualRenameControl: some View {
        Button {
            showManualRenamePopover.toggle()
        } label: {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Circle()
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(showManualRenamePopover ? 0.5 : 0.3),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: Color.black.opacity(0.08), radius: 2, x: 0, y: 1)

                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(showManualRenamePopover ? Color.accentColor : Color.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("PreviewManualRenameButton-\(file.id.uuidString)")
        .help("Open manual rename options")
        .popover(isPresented: $showManualRenamePopover, arrowEdge: .bottom) {
            manualRenamePopover
        }
    }

    private var manualRenamePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 28, height: 28)

                    Image(systemName: "pencil.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("Manual Rename")
                        .font(.caption)
                        .fontWeight(.semibold)
                    Text(file.displayName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            Button {
                startEditing(initialValue: activeFilenameForEditing)
                showManualRenamePopover = false
            } label: {
                Text("Start Rename")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.14))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("PreviewManualRenameStart-\(file.id.uuidString)")

            Divider()
                .opacity(0.5)

            Text("Add steering for next regenerate (optional)")
                .font(.caption2)
                .foregroundStyle(.secondary)

            TextField("e.g. Use YYYY-MM-DD format for screenshots", text: $steeringInstructionDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(2...4)
                .accessibilityIdentifier("PreviewManualRenameSteeringField-\(file.id.uuidString)")

            Button("Add Steering") {
                addSteeringInstruction()
            }
            .buttonStyle(.sortySecondary(size: .small))
            .disabled(steeringInstructionDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .accessibilityIdentifier("PreviewManualRenameAddSteering-\(file.id.uuidString)")
        }
        .padding(14)
        .frame(minWidth: 280, maxWidth: 360)
    }

    private func addSteeringInstruction() {
        let trimmed = steeringInstructionDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let existing = organizer.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if existing.isEmpty {
            organizer.customInstructions = trimmed
        } else {
            organizer.customInstructions = existing + "\n" + trimmed
        }

        if learningsManager.consentManager.canCollectData {
            let folderPath = appState.selectedDirectory?.path
                ?? URL(fileURLWithPath: file.path).deletingLastPathComponent().path
            NotificationCenter.default.post(
                name: .steeringPromptProvided,
                object: nil,
                userInfo: ["prompt": trimmed, "folderPath": folderPath]
            )
        }

        onFocusInstructions?()
        steeringInstructionDraft = ""
        HapticFeedbackManager.shared.success()
    }
}

// MARK: - Flat Unorganized Header View

struct FlatUnorganizedHeaderView: View {
    let fileCount: Int
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    @State private var isDropTarget = false
    
    var body: some View {
        HStack {
            Image(systemName: "questionmark.folder")
                .foregroundColor(.orange)
            Text("Unorganized Files")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text("\(fileCount) files")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isDropTarget ? Color.orange.opacity(0.1) : Color.clear)
                .strokeBorder(isDropTarget ? Color.orange : Color.clear, lineWidth: 2)
        )
        .onDrop(of: [.text], delegate: OptimizedUnorganizedDropDelegate(
            store: store,
            draggedFile: $dragDropManager.draggedFile,
            isTargeted: $isDropTarget,
            onPlanChanged: onPlanChanged
        ))
    }
}

// MARK: - Flat Unorganized File Row View

struct FlatUnorganizedFileRowView: View {
    let file: FileItem
    @ObservedObject var dragDropManager: DragDropManager
    @ObservedObject var store: PreviewStore
    @EnvironmentObject var appState: AppState

    @State private var isDragging = false

    private var duplicateInfo: DuplicateInfo? {
        store.duplicateMappings[file.id]
    }

    private var isHighlighted: Bool {
        store.highlightedFileID == file.id
    }

    var body: some View {
        HStack {
            FileThumbnailView(url: URL(fileURLWithPath: file.path), size: CGSize(width: 20, height: 20))
            Text(file.displayName)
            Spacer()

            if let dupInfo = duplicateInfo {
                LiquidGlassDuplicateButton(
                    duplicateInfo: dupInfo,
                    handoffDirectory: appState.selectedDirectory,
                    highlightedFileID: $store.highlightedFileID
                )
            }

            Text(file.formattedSize)
                .foregroundColor(.secondary)

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.12) : (isDragging ? Color.accentColor.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? Color.accentColor.opacity(0.3) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
            } label: {
                Label("Open", systemImage: "arrow.up.right.square")
            }
            
            Button {
                NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "")
            } label: {
                Label("Reveal in Finder", systemImage: "folder")
            }
        }
        .onTapGesture(count: 2) {
            NSWorkspace.shared.open(URL(fileURLWithPath: file.path))
        }
        .opacity(isDragging ? 0.5 : 1.0)
        .onDrag {
            isDragging = true
            dragDropManager.startDrag(file)
            return NSItemProvider(object: file.id.uuidString as NSString)
        }
    }
}

// MARK: - Optimized Drop Delegates

struct OptimizedFileDropDelegate: DropDelegate {
    let targetFolderID: UUID
    @ObservedObject var store: PreviewStore
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    let onPlanChanged: () -> Void
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard draggedFile != nil else { return false }
        return true
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        store.moveFile(fileID: file.id, toFolderID: targetFolderID)
        onPlanChanged()
        draggedFile = nil
        isTargeted = false
        
        return true
    }
}

struct OptimizedUnorganizedDropDelegate: DropDelegate {
    @ObservedObject var store: PreviewStore
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    let onPlanChanged: () -> Void
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        return !store.plan.unorganizedFiles.contains { $0.id == file.id }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        store.moveFileToUnorganized(fileID: file.id)
        onPlanChanged()
        draggedFile = nil
        isTargeted = false
        
        return true
    }
}
