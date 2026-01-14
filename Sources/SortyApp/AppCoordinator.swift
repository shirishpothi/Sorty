//
//  AppCoordinator.swift
//  Sorty
//
//  Coordinates background tasks and watched folder automation
//

import Foundation
import Combine
import SwiftUI
import UserNotifications
#if canImport(SortyLib)
import SortyLib
#endif

@MainActor
class AppCoordinator: ObservableObject, FolderWatcherDelegate {
    let folderWatcher = FolderWatcher()
    let organizer: FolderOrganizer
    let watchedFoldersManager: WatchedFoldersManager
    let learningsManager: LearningsManager
    let continuousLearningObserver: ContinuousLearningObserver
    private let notificationManager = NotificationManager.shared
    
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
        requestNotificationPermission()
        
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

        NotificationCenter.default.addObserver(forName: .autoOrganizeDisabledGlobally, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let reason = notification.userInfo?["reason"] as? String ?? "Unknown reason"
            
            Task { @MainActor in
                self.notificationManager.showError(message: "Auto-organization paused: \(reason)", isCritical: true)
            }
        }
        
        // Listen for organization completion
        NotificationCenter.default.addObserver(forName: .organizationDidFinish, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            
            Task { @MainActor in
                if let entry = notification.userInfo?["entry"] as? OrganizationHistoryEntry {
                    let stats = self.extractBatchStats(from: entry)
                    self.notificationManager.showBatchSummary(stats: stats)
                }
            }
        }
    }
    
    /// Extract detailed batch statistics from an organization history entry
    private func extractBatchStats(from entry: OrganizationHistoryEntry) -> BatchSummaryStats {
        let folderName = URL(fileURLWithPath: entry.directoryPath).lastPathComponent
        
        // Count operations by type
        var filesMoved = 0
        var filesRenamed = 0
        var filesTagged = 0
        var foldersCreated = 0
        
        if let operations = entry.operations {
            for op in operations {
                switch op.type {
                case .moveFile:
                    filesMoved += 1
                case .renameFile:
                    filesRenamed += 1
                case .tagFile:
                    filesTagged += 1
                case .createFolder:
                    foldersCreated += 1
                case .deleteFile, .copyFile:
                    break
                }
            }
        } else {
            // Fallback to entry-level stats if operations not available
            filesMoved = entry.filesOrganized
            foldersCreated = entry.foldersCreated
        }
        
        // Determine errors
        let errors = entry.status == .failed ? 1 : 0
        
        // Calculate duration (approximate - from entry timestamp to now, or 0 if we can't determine)
        // Note: For a more accurate duration, we'd need to track start time separately
        let duration: TimeInterval = 0
        
        return BatchSummaryStats(
            filesMoved: filesMoved,
            foldersCreated: foldersCreated,
            filesRenamed: filesRenamed,
            filesTagged: filesTagged,
            duplicatesFound: entry.duplicatesDeleted ?? 0,
            errorsEncountered: errors,
            duration: duration,
            folderName: folderName
        )
    }
    
    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
    
    func folderWatcher(_ watcher: FolderWatcher, didDetectStaleBookmarkFor folder: WatchedFolder, newBookmarkData: Data) {
        var updatedFolder = folder
        updatedFolder.bookmarkData = newBookmarkData
        // Also ensure status is valid
        updatedFolder.accessStatus = .valid
        watchedFoldersManager.updateFolder(updatedFolder)
        print("Coordinator: Updated stale bookmark for \(folder.name)")
    }
    
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>, resolvedURL: URL) {
        guard !newFiles.isEmpty else { return }
        
        Task {
            // Check if we can proceed (e.g. not already organizing)
            // Only allow auto-organize when truly idle - not when viewing results (.completed)
            // This prevents auto-triggering while user is reviewing organization results
            guard organizer.state == .idle else {
                print("Coordinator: Skipping auto-organize for \(folder.name) - organizer busy (state: \(organizer.state))")
                return
            }
            
            // Validate AI provider is configured before attempting organization
            guard organizer.aiClient != nil else {
                print("Coordinator: Cannot auto-organize \(folder.name) - AI provider not configured")
                notificationManager.showError(message: "Could not auto-organize \"\(folder.name)\" - no AI provider configured", isCritical: false)
                return
            }
            
            let startTime = Date()
            
            do {
                folderWatcher.pause(folder) // Prevent loop
                
                watchedFoldersManager.markTriggered(folder)
                
                print("Coordinator: Auto-organizing \(newFiles.count) new files in \(folder.name): \(newFiles)")
                
                // Use Incremental Organization for Smart Drop
                // Use resolvedURL which has security access
                try await organizer.organizeIncremental(
                    directory: resolvedURL, 
                    specificFiles: Array(newFiles),
                    customPrompt: folder.customPrompt,
                    temperature: folder.temperature
                )
                
                // Snapshot is updated inside resume() automatically
                folderWatcher.resume(folder)
                
                let duration = Date().timeIntervalSince(startTime)
                print("Coordinator: Auto-organize completed for \(folder.name) in \(String(format: "%.1f", duration))s")
                
                // Show success notification with detailed stats
                let stats = BatchSummaryStats(
                    filesMoved: newFiles.count,
                    foldersCreated: 0, // Will be updated by .organizationDidFinish if available
                    duration: duration,
                    folderName: folder.name
                )
                notificationManager.showBatchSummary(stats: stats)
                
            } catch {
                print("Coordinator: Auto-organize failed for \(folder.name): \(error)")
                notificationManager.showError(message: "Failed to organize \"\(folder.name)\": \(error.localizedDescription)", isCritical: false)
                folderWatcher.resume(folder)
            }
        }
    }
    
    func calibrateFolder(_ folder: WatchedFolder) {
        Task {
            folderWatcher.pause(folder)
            do {
                try await organizer.organize(directory: folder.url, customPrompt: folder.customPrompt, temperature: folder.temperature)
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
