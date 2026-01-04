//
//  AppCoordinator.swift
//  FileOrganizer
//
//  Coordinates background tasks and watched folder automation
//

import Foundation
import Combine
import SwiftUI
#if canImport(FileOrganizerLib)
import FileOrganizerLib
#endif

@MainActor
class AppCoordinator: ObservableObject, FolderWatcherDelegate {
    let folderWatcher = FolderWatcher()
    let organizer: FolderOrganizer
    let watchedFoldersManager: WatchedFoldersManager
    let learningsManager: LearningsManager
    let continuousLearningObserver: ContinuousLearningObserver
    
    init(organizer: FolderOrganizer, watchedFoldersManager: WatchedFoldersManager, learningsManager: LearningsManager) {
        self.organizer = organizer
        self.watchedFoldersManager = watchedFoldersManager
        self.learningsManager = learningsManager
        self.continuousLearningObserver = ContinuousLearningObserver(
            history: organizer.history,
            learningsManager: learningsManager
        )
        self.folderWatcher.delegate = self
        
        // Initial sync
        self.folderWatcher.syncWithFolders(watchedFoldersManager.folders)
        
        setupNotifications()
        
        // Start observing
        self.continuousLearningObserver.startObserving()
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(forName: .organizationDidRevert, object: nil, queue: .main) { [weak self] notification in
            guard let self = self,
                  let url = notification.userInfo?["url"] as? URL else { return }
            
            Task {
                guard let folder = await self.watchedFoldersManager.folders.first(where: { $0.url.path == url.path }) else { return }
                
                // Just reverted, so we must update snapshot to avoid re-triggering
                print("Coordinator: Revert detected for \(folder.name), updating snapshot to ignore reverted files")
                
                // Pause and Resume will force a snapshot update
                self.folderWatcher.pause(folder)
                self.folderWatcher.resume(folder)
            }
        }
    }
    
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>) {
        guard !newFiles.isEmpty else { return }
        
        Task {
            // Check if we can proceed (e.g. not already organizing)
            guard organizer.state == .idle || organizer.state == .ready || organizer.state == .completed else {
                return
            }
            
            do {
                folderWatcher.pause(folder) // Prevent loop
                
                watchedFoldersManager.markTriggered(folder)
                
                // Use Incremental Organization for Smart Drop
                try await organizer.organizeIncremental(
                    directory: folder.url, 
                    specificFiles: Array(newFiles),
                    customPrompt: folder.customPrompt,
                    temperature: folder.temperature
                )
                
                folderWatcher.resume(folder) // Resume after completion
                
            } catch {
                folderWatcher.resume(folder) // Ensure we resume even on error
            }
        }
    }
    
    func calibrateFolder(_ folder: WatchedFolder) {
        Task {
            folderWatcher.pause(folder)
            do {
                try await organizer.organize(directory: folder.url, customPrompt: folder.customPrompt, temperature: folder.temperature)
                // Note: User still needs to click "Apply" for calibrate, which might be confusing if watcher is paused.
                // Ideally calibrate should just be a manual "Organize" trigger from the UI.
                // We'll let the UI handle the "Apply" state, but we need to ensure resume happens eventually.
                // Actually, if we use the main organizer flow, the user controls it. 
                // We should unpause when they finish or cancel.
                // For simplicity in this iteration, we'll just Auto-Apply for calibrate too if it's auto-organize?
                // No, User asked for "Calibrate" to set baseline. Usually implies manual review.
                // We will NOT auto-apply calibrate. We will resume watcher when state goes back to idle/completed.
                // NOTE: This requires observing state changes which is complex here.
                // Alternative: Just resume immediately? No, that risks loops.
                // Better: Just don't pause for calibrate? But then moves trigger watcher.
                // Strategy: Pause, Run Full Organize, Auto-Apply (since it's explicit action)?
                // Let's stick to: Calibrate = Full Organize + Auto Apply.
                 try await organizer.apply(at: folder.url, dryRun: false)
                 folderWatcher.resume(folder)
            } catch {
                folderWatcher.resume(folder)
            }
        }
    }
    
    func syncWatchedFolders() {
        folderWatcher.syncWithFolders(watchedFoldersManager.folders)
    }
}
