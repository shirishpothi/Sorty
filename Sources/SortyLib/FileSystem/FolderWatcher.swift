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
    func folderWatcher(_ watcher: FolderWatcher, didDetectChangesIn folder: WatchedFolder, newFiles: Set<String>, resolvedURL: URL)
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
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    
    private var pausedFolders: Set<UUID> = []
    private var folderSnapshots: [UUID: Set<String>] = [:]
    private var fileModDates: [UUID: [String: Date]] = [:]
    private var resolvedURLs: [UUID: URL] = [:] // Store resolved security URLs
    private let fileManager = FileManager.default
    
    // Debounce support
    private var debounceWorkItems: [UUID: DispatchWorkItem] = [:]
    private let debounceInterval: TimeInterval = 0.3
    
    // Incremental scanning support
    private var pendingEventPaths: [UUID: Set<String>] = [:]
    private var forcedFullRescan: Set<UUID> = []
    
    // Temp file extensions to ignore
    private static let ignoredExtensions: Set<String> = ["tmp", "download", "partial", "crdownload", "part"]
    private static let ignoredSuffixes: Set<Character> = ["~"]
    private static let ignoredNames: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini"]
    
    // Heartbeat for keeping streams alive
    private var heartbeatTimer: DispatchSourceTimer?
    
    // Stream health monitoring
    private var lastEventTime: [UUID: Date] = [:]
    private var streamStartTime: [UUID: Date] = [:]
    private let stuckStreamThreshold: TimeInterval = 300 // 5 minutes
    
    public init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
        startHeartbeat()
    }
    
    deinit {
        stopAllWatching()
        heartbeatTimer?.cancel()
    }
    
    // MARK: - Public API
    
    /// Pause watching for a specific folder (prevent auto-trigger loops)
    public func pause(_ folder: WatchedFolder) {
        performOnQueueSyncIfNeeded {
            self.pausedFolders.insert(folder.id)
            DebugLogger.log("Paused watching: \(folder.name)")
        }
    }
    
    /// Resume watching
    public func resume(_ folder: WatchedFolder) {
        performOnQueueSyncIfNeeded {
            self.pausedFolders.remove(folder.id)
            // Update snapshot to current state to avoid triggering on changes we just made
            self.updateSnapshot(for: folder)
            DebugLogger.log("Resumed watching: \(folder.name)")
        }
    }
    
    /// Start watching a folder for changes
    public func startWatching(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            self?.startWatchingSync(folder)
        }
    }
    
    private func startWatchingSync(_ folder: WatchedFolder) {
        guard folder.isEnabled else { return }
        
        // Stop existing watcher for this folder if any
        stopWatchingSync(id: folder.id)
        
        // Store folder config
        watchedFolders[folder.id] = folder
        
        var path = folder.path
        
        // Resolve Security Scoped Bookmark if present
        if let bookmarkData = folder.bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData,
                                          options: .withSecurityScope,
                                          relativeTo: nil,
                                          bookmarkDataIsStale: &isStale) {
                
                if resolvedURL.startAccessingSecurityScopedResource() {
                    resolvedURLs[folder.id] = resolvedURL
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
        updateSnapshot(for: folder)
        
        createStream(for: folder, at: path)
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
                        self.startWatchingSync(folder)
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
            // Release the retained context on creation failure
            Unmanaged<FolderWatcherContext>.fromOpaque(info).release()
            callbackContexts.removeValue(forKey: folder.id)
            return
        }
        
        FSEventStreamSetDispatchQueue(stream, queue)
        if FSEventStreamStart(stream) {
            streams[folder.id] = stream
            streamStartTime[folder.id] = Date()
            lastEventTime[folder.id] = Date()
            DebugLogger.log("FSEvents: Started watching \(path)")
        } else {
            DebugLogger.log("FSEvents: Failed to start stream for \(path)")
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            // Release the retained context on start failure
            Unmanaged<FolderWatcherContext>.fromOpaque(info).release()
            callbackContexts.removeValue(forKey: folder.id)
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
        fileModDates.removeValue(forKey: id)
        debounceWorkItems[id]?.cancel()
        debounceWorkItems.removeValue(forKey: id)
        pausedFolders.remove(id)
        watchedFolders.removeValue(forKey: id)
        pendingEventPaths.removeValue(forKey: id)
        forcedFullRescan.remove(id)
        
        // Release security scoped resource
        if let url = resolvedURLs[id] {
            url.stopAccessingSecurityScopedResource()
            resolvedURLs.removeValue(forKey: id)
            DebugLogger.log("Stopped accessing security scoped resource for folder ID: \(id)")
        }
        
        lastEventTime.removeValue(forKey: id)
        streamStartTime.removeValue(forKey: id)
    }
    
    private func updateSnapshot(for folder: WatchedFolder) {
        let path = resolvedURLs[folder.id]?.path ?? folder.path
        let modDates = recursiveFileState(atRootPath: path)
        let files = Set(modDates.keys)
        folderSnapshots[folder.id] = Set(files)
        fileModDates[folder.id] = modDates
    }
    
    private static func isIgnoredFile(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if ignoredNames.contains(name) { return true }
        if let lastChar = name.last, ignoredSuffixes.contains(lastChar) { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        if ignoredExtensions.contains(ext) { return true }
        return false
    }

    private func recursiveFileState(atRootPath rootPath: String) -> [String: Date] {
        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .contentModificationDateKey],
            options: [.skipsPackageDescendants, .skipsHiddenFiles]
        ) else {
            return [:]
        }

        var modDates: [String: Date] = [:]

        for case let fileURL as URL in enumerator {
            let name = fileURL.lastPathComponent
            if Self.isIgnoredFile(name) {
                if let values = try? fileURL.resourceValues(forKeys: [.isDirectoryKey]), values.isDirectory == true {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]) else {
                continue
            }

            guard values.isRegularFile == true else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            modDates[relativePath] = values.contentModificationDate ?? Date.distantPast
        }

        return modDates
    }
    
    private func incrementalFileState(changedPaths: Set<String>, rootPath: String, existingModDates: [String: Date]) -> [String: Date] {
        var modDates = existingModDates
        
        // Get unique parent directories of changed paths
        let changedDirs = Set(changedPaths.compactMap { path -> String? in
            let url = URL(fileURLWithPath: path)
            let parent = url.deletingLastPathComponent().path
            guard parent.hasPrefix(rootPath) else { return nil }
            return parent
        })
        
        // Also include the root if any direct children changed
        var dirsToScan = changedDirs
        if changedPaths.contains(where: { URL(fileURLWithPath: $0).deletingLastPathComponent().path == rootPath }) {
            dirsToScan.insert(rootPath)
        }
        
        // For each changed directory, do a shallow enumeration
        for dir in dirsToScan {
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            // Track what files currently exist in this dir
            var currentFilesInDir = Set<String>()
            
            for fileURL in contents {
                let name = fileURL.lastPathComponent
                guard !Self.isIgnoredFile(name) else { continue }
                
                guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                      values.isRegularFile == true else { continue }
                
                let relativePath = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
                currentFilesInDir.insert(relativePath)
                modDates[relativePath] = values.contentModificationDate ?? Date.distantPast
            }
            
            // Remove files that were deleted from this directory
            let dirRelativePrefix = dir == rootPath ? "" : dir.replacingOccurrences(of: rootPath + "/", with: "") + "/"
            let existingInDir = modDates.keys.filter { key in
                if dirRelativePrefix.isEmpty {
                    return !key.contains("/")
                }
                return key.hasPrefix(dirRelativePrefix) && !key.dropFirst(dirRelativePrefix.count).contains("/")
            }
            for existingKey in existingInDir {
                if !currentFilesInDir.contains(existingKey) {
                    modDates.removeValue(forKey: existingKey)
                }
            }
        }
        
        return modDates
    }
    
    fileprivate func handleEvents(for folderId: UUID, changedPaths: Set<String>, requiresFullRescan: Bool) {
        lastEventTime[folderId] = Date()
        guard let folder = watchedFolders[folderId] else { return }
        guard folder.autoOrganize else { return }
        guard !pausedFolders.contains(folderId) else {
            DebugLogger.log("Watcher paused for \(folder.name), ignoring event")
            return
        }
        
        // Accumulate event paths
        if pendingEventPaths[folderId] != nil {
            pendingEventPaths[folderId]?.formUnion(changedPaths)
        } else {
            pendingEventPaths[folderId] = changedPaths
        }
        
        if requiresFullRescan {
            forcedFullRescan.insert(folderId)
        }
        
        debounceWorkItems[folderId]?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.processChanges(for: folderId)
        }
        debounceWorkItems[folderId] = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
    
    private func processChanges(for folderId: UUID) {
        guard let folder = watchedFolders[folderId] else { return }
        guard !pausedFolders.contains(folderId) else { return }
        
        let path = resolvedURLs[folderId]?.path ?? folder.path
        let previousModDates = fileModDates[folderId] ?? [:]
        
        let useFullRescan = forcedFullRescan.contains(folderId)
        let changedPaths = pendingEventPaths[folderId] ?? []
        
        // Clear pending state
        pendingEventPaths.removeValue(forKey: folderId)
        forcedFullRescan.remove(folderId)

        let modDates: [String: Date]
        if useFullRescan || changedPaths.isEmpty || previousModDates.isEmpty {
            modDates = recursiveFileState(atRootPath: path)
        } else {
            modDates = incrementalFileState(changedPaths: changedPaths, rootPath: path, existingModDates: previousModDates)
        }
        
        let currentSet = Set(modDates.keys)
        let previousSet = folderSnapshots[folderId] ?? []
        
        var genuineNewFiles = Set<String>()
        
        let brandNewFiles = currentSet.subtracting(previousSet)
        genuineNewFiles.formUnion(brandNewFiles)
        
        let existingFiles = currentSet.intersection(previousSet)
        for file in existingFiles {
            if let modDate = modDates[file],
               let previousMod = previousModDates[file],
               modDate > previousMod {
                genuineNewFiles.insert(file)
            }
        }

        let newModDates = modDates
        folderSnapshots[folderId] = currentSet
        fileModDates[folderId] = newModDates
        
        guard !genuineNewFiles.isEmpty else { return }
        
        DebugLogger.log("New/changed files detected in \(folder.name): \(genuineNewFiles)")
        
        let resolvedURL = resolvedURLs[folderId] ?? folder.url
        
        Task { @MainActor in
            self.delegate?.folderWatcher(self, didDetectChangesIn: folder, newFiles: genuineNewFiles, resolvedURL: resolvedURL)
        }
    }
    
    // Heartbeat to ensure streams stay alive (sometimes they can get stuck)
    private func startHeartbeat() {
        heartbeatTimer = DispatchSource.makeTimerSource(queue: queue)
        heartbeatTimer?.schedule(deadline: .now() + 60, repeating: 60)
        heartbeatTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Poll for missed changes and refresh quiet streams periodically.
            for (id, folder) in self.watchedFolders {
                guard !self.pausedFolders.contains(id) else { continue }

                let lastSeen = self.lastEventTime[id] ?? self.streamStartTime[id] ?? Date.distantPast
                if Date().timeIntervalSince(lastSeen) > self.stuckStreamThreshold {
                    DebugLogger.log("Heartbeat poll for quiet watcher: \(folder.name)")
                    self.processChanges(for: id)
                    self.lastEventTime[id] = Date()

                    DebugLogger.log("Refreshing quiet stream for: \(folder.name)")
                    self.stopWatchingSync(id: id)
                    self.startWatchingSync(folder)
                }
            }
        }
        heartbeatTimer?.resume()
    }

    private func performOnQueueSyncIfNeeded(_ block: @escaping () -> Void) {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            block()
        } else {
            queue.sync(execute: block)
        }
    }
    
    // MARK: - Public Health & Recovery Methods
    
    /// Re-acquire security-scoped access if lost (e.g., volume disconnect)
    public func reacquireAccessIfNeeded(for folder: WatchedFolder) -> Bool {
        guard let bookmarkData = folder.bookmarkData else { return false }
        
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmarkData,
                                  options: .withSecurityScope,
                                  relativeTo: nil,
                                  bookmarkDataIsStale: &isStale) else {
            DebugLogger.log("Failed to resolve bookmark for reacquire: \(folder.name)")
            return false
        }
        
        if url.startAccessingSecurityScopedResource() {
            queue.async { [weak self] in
                self?.resolvedURLs[folder.id] = url
            }
            DebugLogger.log("Reacquired access for: \(folder.name)")
            return true
        }
        DebugLogger.log("Failed to reacquire access for: \(folder.name)")
        return false
    }
    
    /// Check if a folder is healthy and accessible
    public func isFolderHealthy(_ folder: WatchedFolder) -> Bool {
        var resolvedURL: URL?
        queue.sync {
            resolvedURL = resolvedURLs[folder.id]
        }
        guard let url = resolvedURL else { return false }
        return fileManager.isReadableFile(atPath: url.path)
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
    
    // Extract event paths from the CFArray (kFSEventStreamCreateFlagUseCFTypes)
    var changedPaths = Set<String>()
    var requiresFullRescan = false
    
    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    for i in 0..<numEvents {
        let flags = eventFlags[i]
        
        if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 ||
           flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
            requiresFullRescan = true
        }
        
        if let cfPath = CFArrayGetValueAtIndex(cfPaths, i) {
            let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            changedPaths.insert(path)
        }
    }
    
    watcher.handleEvents(for: folderId, changedPaths: changedPaths, requiresFullRescan: requiresFullRescan)
}

// Add extension to handle private method access in callback workaround if needed,
// but since callback is global, we exposed handleEvents as internal (default) or effectively internal.
// Since FolderWatcher is public, handleEvents needs to be accessible.
// We'll make handleEvents fileprivate and put callback in same file.

extension FolderWatcher {
    fileprivate func handleEventsPublicWrapper(for folderId: UUID, changedPaths: Set<String>, requiresFullRescan: Bool) {
        handleEvents(for: folderId, changedPaths: changedPaths, requiresFullRescan: requiresFullRescan)
    }
}
