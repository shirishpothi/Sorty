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
    
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>) {
        guard !newFiles.isEmpty else { return }
        
        Task {
            // Check if we can proceed (e.g. not already organizing)
            guard organizer.state == .idle || organizer.state == .ready || organizer.state == .completed else {
                print("Coordinator: Skipping auto-organize for \(folder.name) - organizer busy (state: \(organizer.state))")
                return
            }
            
            // Validate AI provider is configured before attempting organization
            guard organizer.aiClient != nil else {
                print("Coordinator: Cannot auto-organize \(folder.name) - AI provider not configured")
                sendNotification(
                    title: "Organization Failed",
                    body: "Could not auto-organize \"\(folder.name)\" because no AI provider is configured."
                )
                return
            }
            
            do {
                folderWatcher.pause(folder) // Prevent loop
                
                watchedFoldersManager.markTriggered(folder)
                
                print("Coordinator: Auto-organizing \(newFiles.count) new files in \(folder.name): \(newFiles)")
                
                // Use Incremental Organization for Smart Drop
                try await organizer.organizeIncremental(
                    directory: folder.url, 
                    specificFiles: Array(newFiles),
                    customPrompt: folder.customPrompt,
                    temperature: folder.temperature
                )
                
                // Snapshot is updated inside resume() automatically
                folderWatcher.resume(folder)
                
                print("Coordinator: Auto-organize completed for \(folder.name)")
                
                // Optional: success notification
                // sendNotification(title: "Files Organized", body: "Successfully organized \(newFiles.count) new files in \(folder.name).")
                
            } catch {
                print("Coordinator: Auto-organize failed for \(folder.name): \(error)")
                sendNotification(
                    title: "Organization Failed",
                    body: "Failed to organize \"\(folder.name)\": \(error.localizedDescription)"
                )
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
    
    private func sendNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
