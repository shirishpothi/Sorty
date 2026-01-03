//
//  FileDropDelegate.swift
//  FileOrganizer
//
//  Handles drag and drop operations for interactive plan editing
//

import SwiftUI
import UniformTypeIdentifiers
import Combine

/// Delegate for handling file drops between folders in PreviewView
struct FileDropDelegate: DropDelegate {
    let targetFolder: FolderSuggestion
    @Binding var plan: OrganizationPlan
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        // Validate that we have a file being dragged
        guard draggedFile != nil else { return false }
        
        // Don't allow dropping on the same folder
        if let file = draggedFile {
            if targetFolder.files.contains(where: { $0.id == file.id }) {
                return false
            }
        }
        
        return true
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        // Remove file from its current location and add to target folder
        var updatedPlan = plan
        
        // Remove from current location
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            removeFileFromFolder(file, from: folder)
        }
        
        // Also check unorganized files
        updatedPlan.unorganizedFiles.removeAll { $0.id == file.id }
        
        // Add to target folder
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            addFileToFolder(file, to: folder, targetId: targetFolder.id)
        }
        
        // Increment version
        var finalPlan = updatedPlan
        finalPlan = OrganizationPlan(
            id: updatedPlan.id,
            suggestions: updatedPlan.suggestions,
            unorganizedFiles: updatedPlan.unorganizedFiles,
            unorganizedDetails: updatedPlan.unorganizedDetails,
            notes: updatedPlan.notes,
            timestamp: Date(),
            version: updatedPlan.version + 1
        )
        
        plan = finalPlan
        draggedFile = nil
        isTargeted = false
        
        return true
    }
    
    // MARK: - Helper Functions
    
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
            // Don't add if already exists
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

/// Delegate for dropping files into the unorganized section
struct UnorganizedDropDelegate: DropDelegate {
    @Binding var plan: OrganizationPlan
    @Binding var draggedFile: FileItem?
    @Binding var isTargeted: Bool
    
    func dropEntered(info: DropInfo) {
        isTargeted = true
    }
    
    func dropExited(info: DropInfo) {
        isTargeted = false
    }
    
    func validateDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        // Don't allow if already in unorganized
        return !plan.unorganizedFiles.contains { $0.id == file.id }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        guard let file = draggedFile else { return false }
        
        var updatedPlan = plan
        
        // Remove from all folders
        updatedPlan.suggestions = updatedPlan.suggestions.map { folder in
            removeFileFromFolder(file, from: folder)
        }
        
        // Add to unorganized
        if !updatedPlan.unorganizedFiles.contains(where: { $0.id == file.id }) {
            updatedPlan.unorganizedFiles.append(file)
        }
        
        // Increment version
        let finalPlan = OrganizationPlan(
            id: updatedPlan.id,
            suggestions: updatedPlan.suggestions,
            unorganizedFiles: updatedPlan.unorganizedFiles,
            unorganizedDetails: updatedPlan.unorganizedDetails,
            notes: updatedPlan.notes,
            timestamp: Date(),
            version: updatedPlan.version + 1
        )
        
        plan = finalPlan
        draggedFile = nil
        isTargeted = false
        
        return true
    }
    
    private func removeFileFromFolder(_ file: FileItem, from folder: FolderSuggestion) -> FolderSuggestion {
        var updatedFolder = folder
        updatedFolder.files.removeAll { $0.id == file.id }
        updatedFolder.subfolders = updatedFolder.subfolders.map { subfolder in
            removeFileFromFolder(file, from: subfolder)
        }
        return updatedFolder
    }
}

/// View model for managing drag state across the preview
@MainActor
class DragDropManager: ObservableObject {
    @Published var draggedFile: FileItem?
    @Published var targetFolderId: UUID?
    
    func startDrag(_ file: FileItem) {
        draggedFile = file
    }
    
    func endDrag() {
        draggedFile = nil
        targetFolderId = nil
    }
    
    func setTarget(_ folderId: UUID?) {
        targetFolderId = folderId
    }
}
