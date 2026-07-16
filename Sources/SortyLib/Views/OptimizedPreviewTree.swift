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
    
    /// Count of user edits captured for learning this session (moves, rejections, renames)
    @Published private(set) var editsCapturedCount: Int = 0
    
    /// Triggers a brief pulse animation when a new edit is captured
    @Published private(set) var editCapturedPulse: Bool = false
    
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
    
    /// Weak reference to learnings manager for recording user actions in the preview
    weak var learningsManager: LearningsManager?
    
    init(plan: OrganizationPlan) {
        self.plan = plan
        expandAllFolders()
        rebuildFlattenedRows()
        cachedPlanVersion = plan.version
        throttledTotalFileCount = plan.totalFiles
    }
    
    func updatePlan(_ newPlan: OrganizationPlan) {
        // Only invalidate caches if plan actually changed (by version or content)
        let planChanged = newPlan.version != cachedPlanVersion || newPlan.id != plan.id
        self.plan = newPlan
        
        if planChanged {
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
    
    /// Record that a user edit was captured for learning
    /// Increments counter and triggers a brief pulse animation
    private func recordEditCaptured() {
        guard learningsManager?.consentManager.canCollectData == true else { return }
        guard learningsManager?.sessionLearningPaused != true else { return }
        editsCapturedCount += 1
        
        // Trigger pulse animation
        withAnimation(.easeOut(duration: 0.15)) {
            editCapturedPulse = true
        }
        
        // Reset pulse after brief delay
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000) // 200ms
            withAnimation(.easeIn(duration: 0.1)) {
                editCapturedPulse = false
            }
        }
    }
    
    /// Reset edit capture count (called when plan resets or regenerates)
    func resetEditsCaptured() {
        editsCapturedCount = 0
        editCapturedPulse = false
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
        
        // Record rejection before mutating the plan
        learningsManager?.recordRejection(originalPath: file.path)
        recordEditCaptured()
        
        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            updatedPlan.suggestions[i] = removeFileFromFolder(file, from: updatedPlan.suggestions[i])
        }
        
        if !updatedPlan.unorganizedFiles.contains(where: { $0.id == fileID }) {
            updatedPlan.unorganizedFiles.append(file)
        }
        
        updateInternalPlan(updatedPlan)
    }
    
    func updateRename(fileID: UUID, folderID: UUID, newName: String) {
        // Record rename edit before mutating the plan
        if let file = findFile(by: fileID),
           let mapping = renameMappings[fileID], mapping.hasRename {
            learningsManager?.recordRenameFeedback(
                originalName: file.displayName,
                suggestedName: mapping.suggestedName,
                finalName: newName,
                folderPath: folderIDToPath[folderID],
                action: .edit,
                confidence: mapping.renameConfidence
            )
            recordEditCaptured()
        }
        
        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            if let updated = updateRenameInFolder(updatedPlan.suggestions[i], targetID: folderID, fileID: fileID, newName: newName) {
                updatedPlan.suggestions[i] = updated
                updateInternalPlan(updatedPlan)
                return
            }
        }
    }
    
    func rejectRename(fileID: UUID, folderID: UUID) {
        // Record rename rejection before mutating the plan
        if let file = findFile(by: fileID),
           let mapping = renameMappings[fileID], mapping.hasRename {
            learningsManager?.recordRenameFeedback(
                originalName: file.displayName,
                suggestedName: mapping.suggestedName,
                finalName: nil,
                folderPath: folderIDToPath[folderID],
                action: .reject,
                confidence: mapping.renameConfidence
            )
            recordEditCaptured()
        }
        
        var updatedPlan = plan
        for i in 0..<updatedPlan.suggestions.count {
            if let updated = rejectRenameInFolder(updatedPlan.suggestions[i], targetID: folderID, fileID: fileID) {
                updatedPlan.suggestions[i] = updated
                updateInternalPlan(updatedPlan)
                return
            }
        }
    }

    func regenerateRename(fileID: UUID, folderID: UUID) {
        guard let file = findFile(by: fileID) else { return }
        let candidate = localRenameCandidate(for: file)
        updateRename(fileID: fileID, folderID: folderID, newName: candidate)
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
        
        // Record rejections for all files being reverted from this folder
        for file in filesToMove {
            learningsManager?.recordRejection(originalPath: file.path)
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

    private func localRenameCandidate(for file: FileItem) -> String {
        let ext = file.extension
        let baseCandidate: String

        if let title = file.contentMetadata?.documentTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseCandidate = title
        } else if let keywords = file.contentMetadata?.detectedKeywords, !keywords.isEmpty {
            baseCandidate = keywords.prefix(4).joined(separator: " ")
        } else if let preview = file.contentMetadata?.allTextContent, !preview.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            baseCandidate = preview.components(separatedBy: .newlines).first ?? preview
        } else {
            baseCandidate = (file.displayName as NSString).deletingPathExtension
                .replacingOccurrences(of: #"(?i)\b(IMG|DSC|Screenshot|Screen Shot|Document|Copy of)[_\s-]*"#, with: "", options: .regularExpression)
        }

        let rawName = ext.isEmpty ? baseCandidate : "\(baseCandidate).\(ext)"
        return FilenameNormalizer.normalize(
            rawName,
            originalFilename: file.displayName,
            options: .default
        ) ?? rawName
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
        
        // Record the manual correction (user moved file to a different folder)
        let destFolderPath = folderIDToPath[toFolderID] ?? ""
        let destPath = destFolderPath.isEmpty ? file.displayName : "\(destFolderPath)/\(file.displayName)"
        learningsManager?.recordCorrection(originalPath: file.path, newPath: destPath)
        recordEditCaptured()
        
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
}

// MARK: - Optimized Preview Tree View

struct OptimizedPreviewTree: View {
    @ObservedObject var store: PreviewStore
    @ObservedObject var dragDropManager: DragDropManager
    let onPlanChanged: () -> Void
    
    var body: some View {
        ScrollViewReader { scrollProxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(store.flattenedRows, id: \.id) { row in
                        FlattenedRowView(
                            row: row,
                            store: store,
                            dragDropManager: dragDropManager,
                            onPlanChanged: onPlanChanged
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
                onPlanChanged: onPlanChanged
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
    @State private var showStoragePopover = false
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
                    .numericTextTransition(
                        animationValue: store.getCachedFileCount(for: suggestion.id) {
                            suggestion.totalFileCount
                        }
                    )

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
                    .fill(isDropTarget ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1) : Color.clear)
                    .strokeBorder(isDropTarget ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.55) : Color.clear, lineWidth: 1.5)
            )
            .contextMenu {
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
                "Couldn't Change Storage Location",
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
        Button {
            showStoragePopover.toggle()
        } label: {
            Image(systemName: "externaldrive")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(showStoragePopover ? .primary : .secondary)
                .frame(width: 18, height: 18)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("StorageLocationMenuButton")
        .help("Storage location options")
        .popover(isPresented: $showStoragePopover, arrowEdge: .bottom) {
            StorageLocationPopoverContent(
                displayName: usedStorageDisplayName,
                path: usedStoragePath,
                onChangeLocation: {
                    showStoragePopover = false
                    showStorageLocationPicker = true
                },
                onShowInFinder: {
                    showStoragePopover = false
                    revealStorageLocationInFinder()
                },
                onCopyPath: {
                    showStoragePopover = false
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(usedStoragePath, forType: .string)
                }
            )
            .systemLiquidGlassPopover(cornerRadius: 12)
        }
    }

    private func finderIcon(for path: String) -> some View {
        AppKitImageView(
            image: NSWorkspace.shared.icon(forFile: path),
            size: CGSize(width: 12, height: 12),
            cornerRadius: 2
        )
        .frame(width: 12, height: 12)
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
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var learningsManager: LearningsManager
    @EnvironmentObject var settingsViewModel: SettingsViewModel
    
    @State private var isDragging = false
    @State private var isEditingName = false
    @State private var editedName = ""
    @State private var isRegeneratingName = false
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

    private var unchangedReason: String? {
        guard let mapping = renameMapping, !mapping.hasRename else { return nil }
        let trimmed = mapping.renameReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
                } else {
                    if let mapping = renameMapping, mapping.hasRename {
                        RenameNameChangeView(
                            originalName: file.displayName,
                            suggestedName: mapping.suggestedName ?? "",
                            helpText: renameHelpText(mapping),
                            isRegenerating: isRegeneratingName
                        )
                    } else {
                        Text(file.displayName)
                            .lineLimit(1)
                            .foregroundColor(.primary)
                    }
                }
                
                Spacer()
                
                if let mapping = renameMapping, mapping.hasRename {
                    Image(systemName: "wand.and.stars")
                        .font(.caption)
                        .foregroundColor(.purple)
                        .help(mapping.renameReason ?? "Sorty suggested rename")

                    RenameActionGlassCluster(
                        isRegenerating: isRegeneratingName,
                        onEdit: {
                            startEditing(initialValue: mapping.suggestedName ?? "")
                        },
                        onRegenerate: {
                            regenerateSuggestedName()
                        },
                        onReject: {
                            store.rejectRename(fileID: file.id, folderID: parentFolderID)
                            onPlanChanged()
                        }
                    )
                }

                if let unchangedReason {
                    RenameReasoningPopoverButton(reason: unchangedReason)
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
            
        }
        .padding(.leading, CGFloat(depth * 16))
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12) : (isDragging ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3) : (isEditingName ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3) : Color.clear), lineWidth: 1)
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
                Button {
                    regenerateSuggestedName()
                } label: {
                    Label("Regenerate Name", systemImage: "arrow.triangle.2.circlepath")
                }

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
    
    private func startEditing(initialValue: String) {
        editedName = initialValue
        isEditingName = true
        isFocused = true
    }
    
    private func saveRename() {
        if !editedName.isEmpty {
            store.updateRename(fileID: file.id, folderID: parentFolderID, newName: editedName)
            onPlanChanged()
        }
        isEditingName = false
    }

    private func regenerateSuggestedName() {
        guard !isRegeneratingName else { return }
        let previousSuggestion = renameMapping?.suggestedName ?? ""
        withAnimation(.easeInOut(duration: 0.2)) {
            isRegeneratingName = true
        }
        HapticFeedbackManager.shared.selection()

        Task {
            do {
                let client = try AIClientFactory.createClient(config: settingsViewModel.config)
                let plan = try await client.analyze(
                    files: [file],
                    customInstructions: renameRegenerationPrompt(),
                    personaPrompt: nil,
                    temperature: 0.8
                )
                let suggestedName = plan.suggestions
                    .lazy
                    .flatMap(\.allFileRenameMappings)
                    .first { $0.originalFile.id == file.id || $0.originalFile.displayName == file.displayName }?
                    .suggestedName
                guard let suggestedName, !suggestedName.isEmpty else {
                    throw AIClientError.invalidResponseFormat
                }
                let normalized = FilenameNormalizer.normalize(
                    suggestedName,
                    originalFilename: file.displayName,
                    options: settingsViewModel.config.renameNamingOptions
                ) ?? suggestedName
                let replacementName = distinctRegeneratedName(normalized, previousSuggestion: previousSuggestion)

                await MainActor.run {
                    store.updateRename(fileID: file.id, folderID: parentFolderID, newName: replacementName)
                    onPlanChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegeneratingName = false
                    }
                    HapticFeedbackManager.shared.success()
                }
            } catch {
                await MainActor.run {
                    let fallbackName = distinctRegeneratedName(
                        previousSuggestion.isEmpty ? file.displayName : previousSuggestion,
                        previousSuggestion: previousSuggestion
                    )
                    store.updateRename(fileID: file.id, folderID: parentFolderID, newName: fallbackName)
                    onPlanChanged()
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isRegeneratingName = false
                    }
                    HapticFeedbackManager.shared.error()
                }
            }
        }
    }

    private func renameRegenerationPrompt() -> String {
        let currentSuggestion = renameMapping?.suggestedName ?? "None"
        let metadata = file.contentMetadata
        let title = metadata?.documentTitle ?? ""
        let keywords = metadata?.detectedKeywords?.prefix(8).joined(separator: ", ") ?? ""
        let contentPreview = String(
            metadata?.allTextContent?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(900) ?? ""
        )

        return """
        Rename only this one file. Keep it in the current folder.

        Original filename: \(file.displayName)
        Current suggested filename: \(currentSuggestion)
        File extension to preserve: \(file.extension)
        Document title: \(title)
        Keywords: \(keywords)
        Content preview:
        \(contentPreview)

        Requirements:
        - Return Sorty's normal JSON organization response.
        - Use a single folder named ".".
        - Preserve the original file extension.
        - Make the name specific, useful, and concise.
        - Spaces are valid if they improve readability.
        - Do not return the current suggested filename. Generate a meaningfully different name.
        - Include suggested_name, rename_reason, and rename_confidence for this file.
        """
    }

    private func distinctRegeneratedName(_ candidate: String, previousSuggestion: String) -> String {
        guard candidate.caseInsensitiveCompare(previousSuggestion) == .orderedSame else {
            return candidate
        }

        let nsName = candidate as NSString
        let ext = nsName.pathExtension
        let base = nsName.deletingPathExtension
        let revised = "\(base) Revised"
        return ext.isEmpty ? revised : "\(revised).\(ext)"
    }
    
    private func cancelRename() {
        isEditingName = false
    }

    private func renameHelpText(_ mapping: FileRenameMapping) -> String {
        let reason = mapping.renameReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return reason.isEmpty ? "Sorty suggested rename" : reason
    }
}

private struct RenameActionGlassCluster: View {
    let isRegenerating: Bool
    let onEdit: () -> Void
    let onRegenerate: () -> Void
    let onReject: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            RenameGlassIconButton(systemImage: "pencil", help: "Edit suggested name", action: onEdit)
            Button(action: onRegenerate) {
                if isRegenerating {
                    SortyGradientCircularLoader(size: 12, lineWidth: 2.2)
                        .frame(width: 16, height: 16)
                } else {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 16, height: 16)
                }
            }
            .buttonStyle(.plain)
            .disabled(isRegenerating)
            .help("Regenerate name with the selected AI model")

            RenameGlassIconButton(systemImage: "xmark.circle", help: "Keep original name", action: onReject)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .systemLiquidGlassBackground(cornerRadius: 10)
    }
}

private struct RenameGlassIconButton: View {
    let systemImage: String
    let help: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 16, height: 16)
        }
        .buttonStyle(.plain)
        .help(help)
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
                .numericTextTransition(animationValue: fileCount)
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
                .fill(isHighlighted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.12) : (isDragging ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.1) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(isHighlighted ? SortyDesignSystem.Colors.resolvedAccent.opacity(0.3) : Color.clear, lineWidth: 1)
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
