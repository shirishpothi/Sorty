//
//  FolderWatcher.swift
//  Sorty
//
//  Monitors directories for file system changes using DispatchSourceFileSystemObject
//

import Foundation

/// Protocol for receiving folder change notifications
@MainActor
public protocol FolderWatcherDelegate: AnyObject {
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>)
}

/// Monitors directories for file changes and triggers organization
public final class FolderWatcher: @unchecked Sendable {
    @MainActor public weak var delegate: FolderWatcherDelegate?
    
    private var sources: [UUID: DispatchSourceFileSystemObject] = [:]
    private var fileDescriptors: [UUID: Int32] = [:]
    private var debounceTimers: [UUID: DispatchWorkItem] = [:]
    private let queue = DispatchQueue(label: "com.sorty.folderwatcher", qos: .utility)
    
    private var pausedFolders: Set<UUID> = []
    private var folderSnapshots: [UUID: Set<String>] = [:]
    private let fileManager = FileManager.default
    
    public init() {}
    
    deinit {
        stopAllWatching()
    }
    
    /// Pause watching for a specific folder (prevent aut-trigger loops)
    public func pause(_ folder: WatchedFolder) {
        pausedFolders.insert(folder.id)
    }
    
    /// Resume watching
    public func resume(_ folder: WatchedFolder) {
        pausedFolders.remove(folder.id)
        // Update snapshot to current state to avoid triggering on changes we just made
        updateSnapshot(for: folder)
    }
    
    private func updateSnapshot(for folder: WatchedFolder) {
        let contents = (try? fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
        folderSnapshots[folder.id] = Set(contents)
    }
    
    /// Start watching a folder for changes
    public func startWatching(_ folder: WatchedFolder) {
        guard folder.isEnabled else { return }
        
        // Stop existing watcher for this folder if any
        stopWatching(folder)
        
        // Take initial snapshot
        updateSnapshot(for: folder)
        
        let path = folder.path
        let fd = open(path, O_EVTONLY)
        
        guard fd >= 0 else {
            DebugLogger.log("Failed to open file descriptor for: \(path)")
            return
        }
        
        fileDescriptors[folder.id] = fd
        
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .delete, .rename, .extend],
            queue: queue
        )
        
        source.setEventHandler { [weak self] in
            self?.handleEvent(for: folder)
        }
        
        source.setCancelHandler { [weak self] in
            if let fd = self?.fileDescriptors[folder.id] {
                close(fd)
            }
            self?.fileDescriptors.removeValue(forKey: folder.id)
        }
        
        sources[folder.id] = source
        source.resume()
        
        DebugLogger.log("Started watching: \(folder.name)")
    }
    
    /// Stop watching a specific folder
    public func stopWatching(_ folder: WatchedFolder) {
        stopWatching(id: folder.id)
    }
    
    private func stopWatching(id: UUID) {
        // Cancel debounce timer
        debounceTimers[id]?.cancel()
        debounceTimers.removeValue(forKey: id)
        
        // Cancel and release source
        if let source = sources[id] {
            source.cancel()
            sources.removeValue(forKey: id)
        }
        
        folderSnapshots.removeValue(forKey: id)
        pausedFolders.remove(id)
    }
    
    /// Stop watching all folders
    public func stopAllWatching() {
        for (id, _) in sources {
            stopWatching(id: id)
        }
    }
    
    /// Update watched folders based on provided list
    public func syncWithFolders(_ folders: [WatchedFolder]) {
        let currentIds = Set(sources.keys)
        let folderIds = Set(folders.map { $0.id })
        
        // Stop watching folders that were removed
        for id in currentIds.subtracting(folderIds) {
            stopWatching(id: id)
        }
        
        // Start or update watching for current folders
        for folder in folders {
            if folder.isEnabled {
                if sources[folder.id] == nil {
                    startWatching(folder)
                }
            } else {
                stopWatching(folder)
            }
        }
    }
    
    // MARK: - Private
    
    private func handleEvent(for folder: WatchedFolder) {
        guard folder.autoOrganize else { return }
        guard !pausedFolders.contains(folder.id) else {
            DebugLogger.log("Watcher paused for \(folder.name), ignoring event")
            return
        }
        
        // Debounce: cancel previous timer and start new one
        debounceTimers[folder.id]?.cancel()
        
        let delay = folder.triggerDelay
        
        let workItem = DispatchWorkItem { [weak self] in
            guard let self = self else { return }
            
            // Re-check pause state (might have paused during debounce)
            guard !self.pausedFolders.contains(folder.id) else { return }
            
            // Diffing Logic
            let currentContents = (try? self.fileManager.contentsOfDirectory(atPath: folder.path)) ?? []
            let currentSet = Set(currentContents)
            let previousSet = self.folderSnapshots[folder.id] ?? []
            
            let newFiles = currentSet.subtracting(previousSet)
            
            // Update snapshot
            self.folderSnapshots[folder.id] = currentSet
            
            guard !newFiles.isEmpty else {
                DebugLogger.log("No new files detected in \(folder.name)")
                return
            }
            
            DebugLogger.log("New files detected: \(newFiles)")
            
            Task { @MainActor in
                self.delegate?.folderWatcher(self, didDetectChangesIn: folder, newFiles: newFiles)
            }
        }
        
        debounceTimers[folder.id] = workItem
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
        
        DebugLogger.log("Change detected in \(folder.name), will trigger in \(delay)s")
    }
}
