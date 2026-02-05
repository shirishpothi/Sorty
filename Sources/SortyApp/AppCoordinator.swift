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
    let learningsFSMonitor: LearningsFSMonitor
    private let notificationManager = NotificationManager.shared
    
    init(organizer: FolderOrganizer, watchedFoldersManager: WatchedFoldersManager, learningsManager: LearningsManager) {
        self.organizer = organizer
        self.watchedFoldersManager = watchedFoldersManager
        self.learningsManager = learningsManager
        self.continuousLearningObserver = ContinuousLearningObserver(
            history: organizer.history,
            learningsManager: learningsManager
        )
        self.learningsFSMonitor = LearningsFSMonitor()
        self.folderWatcher.delegate = self
        
        // Inject observer into organizer
        organizer.learningsObserver = self.continuousLearningObserver
        
        // Initial sync
        self.folderWatcher.syncWithFolders(watchedFoldersManager.folders)
        
        setupNotifications()
        requestNotificationPermission()
        
        // Start observing
        self.continuousLearningObserver.startObserving()
        
        // Wire up FSMonitor to ContinuousLearningObserver
        self.learningsFSMonitor.onFileMoveDetected = { [weak self] move in
            Task { @MainActor in
                self?.continuousLearningObserver.handleFileMove(from: move.fromPath, to: move.toPath)
            }
        }
        
        self.learningsFSMonitor.onFileRemoved = { [weak self] path in
            Task { @MainActor in
                self?.continuousLearningObserver.handleFileRemoval(at: path)
            }
        }
        
        // Prewarm connections for all configured AI providers on startup
        Task {
            await AISessionManager.shared.prewarmAllConfigured()
        }
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
            guard let entry = notification.userInfo?["entry"] as? OrganizationHistoryEntry else { return }
            
            Task { @MainActor in
                let stats = self.extractBatchStats(from: entry)
                self.notificationManager.showBatchSummary(stats: stats)
                
                // Start FSMonitor for learning from user corrections
                let folderURL = URL(fileURLWithPath: entry.directoryPath)
                self.learningsFSMonitor.startMonitoring(directory: folderURL)
            }
        }
        
        // Handle "Undo" action from notification
        NotificationCenter.default.addObserver(forName: .undoLastOrganization, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                await self.handleUndoAction(folderPath: folderPath)
            }
        }
        
        // Handle "Open Folder" action from notification
        NotificationCenter.default.addObserver(forName: .openOrganizedFolder, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                self.handleOpenFolderAction(folderPath: folderPath)
            }
        }
        
        // Handle "Retry" action from notification
        NotificationCenter.default.addObserver(forName: .retryLastOrganization, object: nil, queue: .main) { [weak self] notification in
            guard let self = self else { return }
            let folderPath = notification.userInfo?["folderPath"] as? String
            
            Task { @MainActor in
                await self.handleRetryAction(folderPath: folderPath)
            }
        }
        
        // Handle "Show Details" action from notification
        NotificationCenter.default.addObserver(forName: .showOrganizationDetails, object: nil, queue: .main) { [weak self] _ in
            guard let self = self else { return }
            
            Task { @MainActor in
                self.handleShowDetailsAction()
            }
        }
    }
    
    // MARK: - Notification Action Handlers
    
    /// Handle undo action from notification
    private func handleUndoAction(folderPath: String?) async {
        
        // Find the entry to undo
        guard let entryToUndo = findEntryToUndo(folderPath: folderPath) else {
            print("Coordinator: No entry found to undo")
            notificationManager.showError(message: "Nothing to undo", isCritical: false)
            return
        }
        
        guard !entryToUndo.isUndone else {
            print("Coordinator: Entry already undone")
            notificationManager.showError(message: "Already undone", isCritical: false)
            return
        }
        
        print("Coordinator: Undoing organization for \(entryToUndo.directoryPath)")
        
        do {
            let result = try await organizer.undoHistoryEntry(entryToUndo)
            
            let message: String
            if result.hasIssues {
                message = "Undo complete (\(result.successfulOperations) restored, \(result.missingFiles.count) skipped)"
            } else {
                message = "Undo complete - \(result.successfulOperations) files restored"
            }
            
            notificationManager.showInfo(
                title: "Undo Successful",
                message: message
            )
            
        } catch {
            print("Coordinator: Undo failed: \(error)")
            notificationManager.showError(message: "Undo failed: \(error.localizedDescription)", isCritical: false)
        }
    }
    
    /// Find the most recent entry to undo, optionally filtered by folder path
    private func findEntryToUndo(folderPath: String?) -> OrganizationHistoryEntry? {
        let entries = organizer.history.entries
        
        if let path = folderPath {
            // Find the most recent non-undone entry for this specific folder
            return entries.first { $0.directoryPath == path && !$0.isUndone && $0.success }
        } else {
            // Find the most recent non-undone entry
            return entries.first { !$0.isUndone && $0.success }
        }
    }
    
    /// Handle open folder action from notification
    private func handleOpenFolderAction(folderPath: String?) {
        // Get folder path from parameter or last history entry
        let path: String?
        if let fp = folderPath {
            path = fp
        } else if let lastEntry = organizer.history.entries.first {
            path = lastEntry.directoryPath
        } else {
            path = nil
        }
        
        guard let path = path else {
            print("Coordinator: No folder path to open")
            return
        }
        
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
        print("Coordinator: Opened folder \(path)")
    }
    
    /// Handle retry action from notification
    private func handleRetryAction(folderPath: String?) async {
        // Get folder path from parameter or last failed entry
        let path: String?
        if let fp = folderPath {
            path = fp
        } else if let lastFailedEntry = organizer.history.entries.first(where: { $0.status == .failed }) {
            path = lastFailedEntry.directoryPath
        } else {
            path = nil
        }
        
        guard let path = path else {
            print("Coordinator: No folder path to retry")
            notificationManager.showError(message: "No failed operation to retry", isCritical: false)
            return
        }
        
        // Check if we're already busy
        guard organizer.state == .idle else {
            print("Coordinator: Cannot retry - organizer is busy")
            notificationManager.showError(message: "Organizer is busy, try again later", isCritical: false)
            return
        }
        
        print("Coordinator: Retrying organization for \(path)")
        
        do {
            let url = URL(fileURLWithPath: path)
            try await organizer.organize(directory: url, customPrompt: nil, temperature: nil)
            try await organizer.apply(at: url, dryRun: false)
            
            notificationManager.showInfo(
                title: "Retry Successful",
                message: "Organization completed for \(url.lastPathComponent)"
            )
            
        } catch {
            print("Coordinator: Retry failed: \(error)")
            notificationManager.showError(message: "Retry failed: \(error.localizedDescription)", isCritical: false)
        }
    }
    
    /// Handle show details action - bring app to front
    private func handleShowDetailsAction() {
        // Activate the app and bring it to front
        NSApplication.shared.activate(ignoringOtherApps: true)
        
        // Post notification to show history/results view
        NotificationCenter.default.post(name: NSNotification.Name("SortyShowHistoryView"), object: nil)
        
        print("Coordinator: Activated app for details view")
    }
    
    /// Extract detailed batch statistics from an organization history entry
    private func extractBatchStats(from entry: OrganizationHistoryEntry) -> BatchSummaryStats {
        let folderName = URL(fileURLWithPath: entry.directoryPath).lastPathComponent
        let folderPath = entry.directoryPath
        
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
        
        // Check if undo is possible (has operations to undo)
        let canUndo = (entry.operations?.isEmpty == false)
        
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
            folderName: folderName,
            folderPath: folderPath,
            canUndo: canUndo
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
                    temperature: folder.temperature,
                    providerOverride: folder.providerOverride,
                    modelOverride: folder.modelOverride
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
                    folderName: folder.name,
                    folderPath: resolvedURL.path,
                    canUndo: true
                )
                
                // Ensure notification is shown during auto-organization
                // showBatchSummary logic will respect user settings for HUD vs System
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
