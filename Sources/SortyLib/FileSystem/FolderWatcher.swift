//
//  FolderWatcher.swift
//  Sorty
//
//  Monitors directories for file system changes using FSEvents
//  More reliable than DispatchSource for folder monitoring
//

import Foundation
import CoreServices

/// Protocol for receiving folder change notifications
@MainActor
public protocol FolderWatcherDelegate: AnyObject {
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>)
    func folderWatcher(_ watcher: FolderWatcher, didDetectStaleBookmarkFor folder: WatchedFolder, newBookmarkData: Data)
}

/// Monitors directories for file changes and triggers organization
public final class FolderWatcher: @unchecked Sendable {
    @MainActor public weak var delegate: FolderWatcherDelegate?
    
    // FSEvents state
    private var streams: [UUID: FSEventStreamRef] = [:]
    private var callbackContexts: [UUID: UnsafeMutableRawPointer] = [:]
    
    private var watchedFolders: [UUID: WatchedFolder] = [:]
    private let queue = DispatchQueue(label: "com.sorty.folderwatcher", qos: .utility)
    
    private var pausedFolders: Set<UUID> = []
    private var folderSnapshots: [UUID: Set<String>] = [:]
    private var resolvedURLs: [UUID: URL] = [:] // Store resolved security URLs
    private let fileManager = FileManager.default
    
    // Heartbeat for keeping streams alive
    private var heartbeatTimer: DispatchSourceTimer?
    
    public init() {
        startHeartbeat()
    }
    
    deinit {
        stopAllWatching()
        heartbeatTimer?.cancel()
    }
    
    // MARK: - Public API
    
    /// Pause watching for a specific folder (prevent auto-trigger loops)
    public func pause(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            self?.pausedFolders.insert(folder.id)
            DebugLogger.log("Paused watching: \(folder.name)")
        }
    }
    
    /// Resume watching
    public func resume(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.pausedFolders.remove(folder.id)
            // Update snapshot to current state to avoid triggering on changes we just made
            self.updateSnapshot(for: folder)
            DebugLogger.log("Resumed watching: \(folder.name)")
        }
    }
    
    /// Start watching a folder for changes
    public func startWatching(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self = self else { return }
            guard folder.isEnabled else { return }
            
            // Stop existing watcher for this folder if any
            self.stopWatchingSync(id: folder.id)
            
            // Store folder config
            self.watchedFolders[folder.id] = folder
            
            var path = folder.path
            
            // Resolve Security Scoped Bookmark if present
            if let bookmarkData = folder.bookmarkData {
                var isStale = false
                if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData,
                                              options: .withSecurityScope,
                                              relativeTo: nil,
                                              bookmarkDataIsStale: &isStale) {
                    
                    if resolvedURL.startAccessingSecurityScopedResource() {
                        self.resolvedURLs[folder.id] = resolvedURL
                        path = resolvedURL.path
                        DebugLogger.log("Successfully resolved bookmark for: \(path)")
                        
                        // If stale, notify delegate to update storage
                        if isStale {
                            Task { @MainActor [weak self] in
                                guard let self = self else { return }
                                // Re-create bookmark fresh
                                if let newData = try? resolvedURL.bookmarkData(
                                    options: .withSecurityScope,
                                    includingResourceValuesForKeys: nil,
                                    relativeTo: nil
                                ) {
                                    self.delegate?.folderWatcher(self, didDetectStaleBookmarkFor: folder, newBookmarkData: newData)
                                }
                            }
                        }
                    } else {
                        DebugLogger.log("Failed to access security scoped resource for: \(folder.path)")
                    }
                } else {
                    DebugLogger.log("Failed to resolve bookmark data for: \(folder.path)")
                }
            }
            
            // Take initial snapshot
            self.updateSnapshot(for: folder)
            
            self.createStream(for: folder, at: path)
        }
    }
    
    /// Stop watching a specific folder
    public func stopWatching(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            self?.stopWatchingSync(id: folder.id)
        }
    }
    
    /// Stop watching all folders
    public func stopAllWatching() {
        queue.sync {
            let ids = Array(streams.keys)
            for id in ids {
                stopWatchingSync(id: id)
            }
        }
    }
    
    /// Update watched folders based on provided list
    public func syncWithFolders(_ folders: [WatchedFolder]) {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let currentIds = Set(self.watchedFolders.keys)
            let folderIds = Set(folders.map { $0.id })
            
            // 1. Stop watching folders that were removed
            for id in currentIds.subtracting(folderIds) {
                self.stopWatchingSync(id: id)
            }
            
            // 2. Process remaining and new folders
            for folder in folders {
                let existingFolder = self.watchedFolders[folder.id]
                
                if folder.isEnabled {
                    // If path changed or it's new, restart
                    if existingFolder == nil || existingFolder?.path != folder.path {
                        self.startWatching(folder)
                    } else {
                        // Just update metadata (delay, autoOrganize, etc.)
                        self.watchedFolders[folder.id] = folder
                    }
                } else {
                    // If disabled, ensure it's stopped
                    if existingFolder != nil {
                        self.stopWatchingSync(id: folder.id)
                    }
                }
            }
        }
    }
    
    // MARK: - Private Implementation
    
    private func createStream(for folder: WatchedFolder, at path: String) {
        // Prepare context
        var context = FSEventStreamContext(version: 0, info: nil, retain: nil, release: nil, copyDescription: nil)
        
        // Pass self and folderID as info
        let info = UnsafeMutableRawPointer(Unmanaged.passRetained(FolderWatcherContext(watcher: self, folderId: folder.id)).toOpaque())
        context.info = info
        callbackContexts[folder.id] = info
        
        let pathsToWatch = [path] as CFArray
        let latency: TimeInterval = 1.0 // 1 second latency for coalescing events
        
        // Flags: FileLevel events + WatchRoot + NoDefer (deliver immediately after latency)
        let flags = FSEventStreamCreateFlags(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagNoDefer)
        
        guard let stream = FSEventStreamCreate(kCFAllocatorDefault,
                                               callback,
                                               &context,
                                               pathsToWatch,
                                               FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                                               latency,
                                               flags) else {
            DebugLogger.log("Failed to create FSEventStream for \(path)")
            return
        }
        
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            streams[folder.id] = stream
            DebugLogger.log("FSEvents: Started watching \(path)")
        } else {
            DebugLogger.log("FSEvents: Failed to start stream for \(path)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
    }
    
    private func stopWatchingSync(id: UUID) {
        // Stop stream
        if let stream = streams[id] {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streams.removeValue(forKey: id)
        }
        
        // Clean up context
        if let contextPtr = callbackContexts[id] {
            Unmanaged<FolderWatcherContext>.fromOpaque(contextPtr).release()
            callbackContexts.removeValue(forKey: id)
        }
        
        folderSnapshots.removeValue(forKey: id)
        pausedFolders.remove(id)
        watchedFolders.removeValue(forKey: id)
        
        // Release security scoped resource
        if let url = resolvedURLs[id] {
            url.stopAccessingSecurityScopedResource()
            resolvedURLs.removeValue(forKey: id)
            DebugLogger.log("Stopped accessing security scoped resource for folder ID: \(id)")
        }
    }
    
    private func updateSnapshot(for folder: WatchedFolder) {
        // Must be called on queue
        let path = resolvedURLs[folder.id]?.path ?? folder.path
        let contents = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
        // Only track files, not dot files
        let files = contents.filter { !$0.hasPrefix(".") }
        folderSnapshots[folder.id] = Set(files)
    }
    
    fileprivate func handleEvents(for folderId: UUID) {
        guard let folder = watchedFolders[folderId] else { return }
        guard folder.autoOrganize else { return }
        guard !pausedFolders.contains(folderId) else {
            DebugLogger.log("Watcher paused for \(folder.name), ignoring event")
            return
        }
        
        // Resolve path
        let path = resolvedURLs[folderId]?.path ?? folder.path
        
        // Diffing Logic
        let currentContents = (try? fileManager.contentsOfDirectory(atPath: path)) ?? []
        let currentSet = Set(currentContents.filter { !$0.hasPrefix(".") })
        let previousSet = folderSnapshots[folderId] ?? []
        
        let newFiles = currentSet.subtracting(previousSet)
        
        // Update snapshot
        folderSnapshots[folderId] = currentSet
        
        guard !newFiles.isEmpty else {
            return
        }
        
        DebugLogger.log("New files detected in \(folder.name): \(newFiles)")
        
        Task { @MainActor in
            self.delegate?.folderWatcher(self, didDetectChangesIn: folder, newFiles: newFiles)
        }
    }
    
    // Heartbeat to ensure streams stay alive (sometimes they can get stuck)
    private func startHeartbeat() {
        heartbeatTimer = DispatchSource.makeTimerSource(queue: queue)
        heartbeatTimer?.schedule(deadline: .now() + 60, repeating: 60)
        heartbeatTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            // Verify streams are still valid (basic check)
            for (id, stream) in self.streams {
                // If needed, we could check stream status here
                // For now just logging to confirm watcher is alive
                // DebugLogger.log("Heartbeat: Monitoring \(self.watchedFolders[id]?.name ?? "unknown")")
            }
        }
        heartbeatTimer?.resume()
    }
}

// Helper context class
private class FolderWatcherContext {
    weak var watcher: FolderWatcher?
    let folderId: UUID
    
    init(watcher: FolderWatcher, folderId: UUID) {
        self.watcher = watcher
        self.folderId = folderId
    }
}

// C-style callback function
private func callback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let info = clientCallBackInfo else { return }
    let context = Unmanaged<FolderWatcherContext>.fromOpaque(info).takeUnretainedValue()
    
    guard let watcher = context.watcher else { return }
    let folderId = context.folderId
    
    // We received an event batch. Since we rely on snapshotting,
    // we can simply trigger a check. FSEvents coalesces events, so this is efficient.
    
    // Dispatch back to watcher queue to handle safely
    // Note: If we set the dispatch queue on the stream, this callback is already on that queue.
    // However, to be safe and consistent with class structure:
    watcher.handleEvents(for: folderId)
}

// Add extension to handle private method access in callback workaround if needed,
// but since callback is global, we exposed handleEvents as internal (default) or effectively internal.
// Since FolderWatcher is public, handleEvents needs to be accessible.
// We'll make handleEvents fileprivate and put callback in same file.

extension FolderWatcher {
    fileprivate func handleEventsPublicWrapper(for folderId: UUID) {
        handleEvents(for: folderId)
    }
}
