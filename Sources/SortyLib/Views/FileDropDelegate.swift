//
//  FileDropDelegate.swift
//  Sorty
//
//  Handles drag and drop operations for interactive plan editing
//

import SwiftUI
import Combine

/// View model for managing drag state across the preview
@MainActor
class DragDropManager: ObservableObject {
    @Published var draggedFile: FileItem?
    @Published var targetFolderId: UUID?
    
    /// Cached valid drop targets - populated when plan changes, not during dragging
    private var validDropTargets: Set<UUID> = []
    private var cachedPlanVersion: Int = -1
    private var cachedPlanID: UUID?
    
    /// Check if a folder is a valid drop target (uses cache)
    func isValidDropTarget(folderID: UUID, plan: OrganizationPlan) -> Bool {
        // Validate cache is for current plan
        if cachedPlanID != plan.id || cachedPlanVersion != plan.version {
            rebuildValidDropTargetsCache(plan: plan)
        }
        return validDropTargets.contains(folderID)
    }
    
    /// Rebuild the valid drop targets cache - call when plan changes
    func rebuildValidDropTargetsCache(plan: OrganizationPlan) {
        var targets: Set<UUID> = []
        
        func collectFolderIDs(_ folder: FolderSuggestion) {
            targets.insert(folder.id)
            for subfolder in folder.subfolders {
                collectFolderIDs(subfolder)
            }
        }
        
        for suggestion in plan.suggestions {
            collectFolderIDs(suggestion)
        }
        
        validDropTargets = targets
        cachedPlanVersion = plan.version
        cachedPlanID = plan.id
    }
    
    /// Clear the cache (call when plan is explicitly updated)
    func clearDropTargetCache() {
        validDropTargets.removeAll()
        cachedPlanVersion = -1
        cachedPlanID = nil
    }
    
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
