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
    private var rootChangedFolders: Set<UUID> = []
    
    // Temp file extensions to ignore
    private static let ignoredExtensions: Set<String> = ["tmp", "download", "partial", "crdownload", "part"]
    private static let ignoredSuffixes: Set<Character> = ["~"]
    private static let ignoredNames: Set<String> = [".DS_Store", "Thumbs.db", "desktop.ini"]
    
    // Heartbeat for keeping streams alive
    private var heartbeatTimer: DispatchSourceTimer?
    
    // Stream health monitoring
    private var lastEventTime: [UUID: Date] = [:]
    private var streamStartTime: [UUID: Date] = [:]
    private var lastReconciliationTime: [UUID: Date] = [:]
    private let heartbeatInterval: TimeInterval = 300 // 5 minutes
    private let reconciliationInterval: TimeInterval = 900 // 15 minutes
    private lazy var snapshotStoreDirectory: URL? = {
        guard let supportDirectory = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        return supportDirectory
            .appendingPathComponent("Sorty", isDirectory: true)
            .appendingPathComponent("WatcherSnapshots", isDirectory: true)
    }()
    
    public init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
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

    /// Rebuild the baseline snapshot after known in-app file mutations.
    public func refreshSnapshot(for folder: WatchedFolder) {
        performOnQueueSyncIfNeeded {
            self.updateSnapshot(for: folder)
            DebugLogger.log("Refreshed watcher snapshot: \(folder.name)")
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
        
        let restoredPersistedSnapshot = restorePersistedSnapshot(for: folder, currentRootPath: path)

        createStream(for: folder, at: path)
        startHeartbeatIfNeeded()

        if restoredPersistedSnapshot {
            forcedFullRescan.insert(folder.id)
            processChanges(for: folder.id)
        } else {
            // Keep the previous baseline if a removable volume or cloud provider
            // is temporarily unavailable during startup/restart.
            updateSnapshot(for: folder, allowEmptyForUnavailableRoot: false)
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
                self.removePersistedSnapshot(for: id)
            }
            
            // 2. Process remaining and new folders
            for folder in folders {
                let existingFolder = self.watchedFolders[folder.id]
                
                if folder.isEnabled {
                    // If path changed or it's new, restart
                    if existingFolder == nil || self.shouldRestartWatcher(from: existingFolder, to: folder) {
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

    private func shouldRestartWatcher(from existingFolder: WatchedFolder?, to folder: WatchedFolder) -> Bool {
        guard let existingFolder else { return true }
        return existingFolder.path != folder.path || existingFolder.bookmarkData != folder.bookmarkData
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
        
        // Flags: File-level events + watch root + no defer + mark events from this process.
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagMarkSelf
        )
        
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
            startHeartbeatIfNeeded()
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
        rootChangedFolders.remove(id)
        
        // Release security scoped resource
        if let url = resolvedURLs[id] {
            url.stopAccessingSecurityScopedResource()
            resolvedURLs.removeValue(forKey: id)
            DebugLogger.log("Stopped accessing security scoped resource for folder ID: \(id)")
        }
        
        lastEventTime.removeValue(forKey: id)
        streamStartTime.removeValue(forKey: id)
        lastReconciliationTime.removeValue(forKey: id)
        stopHeartbeatIfIdle()
    }
    
    @discardableResult
    private func updateSnapshot(for folder: WatchedFolder, allowEmptyForUnavailableRoot: Bool = true) -> Bool {
        let path = resolvedURLs[folder.id]?.path ?? folder.path
        guard isReadableDirectory(atPath: path) else {
            if allowEmptyForUnavailableRoot || folderSnapshots[folder.id] == nil {
                folderSnapshots[folder.id] = []
                fileModDates[folder.id] = [:]
            }
            DebugLogger.log("Skipped watcher snapshot for unavailable folder: \(folder.name)")
            return false
        }

        let modDates = recursiveFileState(atRootPath: path)
        let files = Set(modDates.keys)
        folderSnapshots[folder.id] = Set(files)
        fileModDates[folder.id] = modDates
        lastReconciliationTime[folder.id] = Date()
        persistSnapshot(folderId: folder.id, rootPath: path, modDates: modDates)
        return true
    }
    
    private static func isIgnoredFile(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if ignoredNames.contains(name) { return true }
        if let lastChar = name.last, ignoredSuffixes.contains(lastChar) { return true }
        let ext = (name as NSString).pathExtension.lowercased()
        if ignoredExtensions.contains(ext) { return true }
        return false
    }

    private func isReadableDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: path)
    }

    private func recursiveFileState(atRootPath rootPath: String) -> [String: Date] {
        guard isReadableDirectory(atPath: rootPath) else {
            return [:]
        }

        guard let enumerator = fileManager.enumerator(
            at: URL(fileURLWithPath: rootPath),
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ],
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

            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ]) else {
                continue
            }

            guard values.isRegularFile == true,
                  !Self.shouldIgnoreCloudPlaceholder(at: fileURL, resourceValues: values) else {
                continue
            }

            let relativePath = fileURL.path.replacingOccurrences(of: rootPath + "/", with: "")
            modDates[relativePath] = values.contentModificationDate ?? Date.distantPast
        }

        return modDates
    }
    
    private func incrementalFileState(changedPaths: Set<String>, rootPath: String, existingModDates: [String: Date]) -> [String: Date] {
        var modDates = existingModDates
        let standardizedRootPath = URL(fileURLWithPath: rootPath).standardizedFileURL.path
        
        // Get unique directories affected by the events. Directory paths are
        // scanned recursively so dropped folders are captured without a
        // full-root pass.
        var recursiveDirsToScan = Set<String>()
        let changedDirs = Set(changedPaths.compactMap { path -> String? in
            let url = URL(fileURLWithPath: path)
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue {
                let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                guard Self.isPath(standardizedPath, within: standardizedRootPath) else { return nil }
                recursiveDirsToScan.insert(standardizedPath)
                return standardizedPath
            } else {
                let parent = url.deletingLastPathComponent().standardizedFileURL.path
                guard Self.isPath(parent, within: standardizedRootPath) else { return nil }
                return parent
            }
        })

        for path in changedPaths where !fileManager.fileExists(atPath: path) {
            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
            guard Self.isPath(standardizedPath, within: standardizedRootPath),
                  let relativePath = Self.relativePath(of: standardizedPath, within: standardizedRootPath),
                  !relativePath.isEmpty else { continue }
            modDates.removeValue(forKey: relativePath)
            let deletedDirectoryPrefix = relativePath + "/"
            for key in modDates.keys where key.hasPrefix(deletedDirectoryPrefix) {
                modDates.removeValue(forKey: key)
            }
        }
        
        // Also include the root if any direct children changed
        var dirsToScan = changedDirs
        if changedPaths.contains(where: {
            URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path == standardizedRootPath
        }) {
            dirsToScan.insert(standardizedRootPath)
        }

        let recursivePrefixes = recursiveDirsToScan.map { dir -> String in
            dir == standardizedRootPath ? "" : (Self.relativePath(of: dir, within: standardizedRootPath) ?? "") + "/"
        }
        for key in modDates.keys where recursivePrefixes.contains(where: { prefix in
            prefix.isEmpty || key.hasPrefix(prefix)
        }) {
            modDates.removeValue(forKey: key)
        }

        for dir in recursiveDirsToScan {
            let recursiveState = recursiveFileState(atRootPath: dir)
            let dirRelativePrefix = dir == standardizedRootPath ? "" : (Self.relativePath(of: dir, within: standardizedRootPath) ?? "") + "/"
            for (relativePath, modDate) in recursiveState {
                modDates[dirRelativePrefix + relativePath] = modDate
            }
        }
        
        // For each remaining changed directory, do a shallow enumeration.
        for dir in dirsToScan {
            guard !recursiveDirsToScan.contains(dir) else { continue }
            let dirURL = URL(fileURLWithPath: dir)
            guard let contents = try? fileManager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .ubiquitousItemDownloadingStatusKey,
                ],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            // Track what files currently exist in this dir
            var currentFilesInDir = Set<String>()
            
            for fileURL in contents {
                let name = fileURL.lastPathComponent
                guard !Self.isIgnoredFile(name) else { continue }
                
                guard let values = try? fileURL.resourceValues(forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                    .ubiquitousItemDownloadingStatusKey,
                ]),
                      values.isRegularFile == true,
                      !Self.shouldIgnoreCloudPlaceholder(at: fileURL, resourceValues: values) else {
                    continue
                }
                
                guard let relativePath = Self.relativePath(
                    of: fileURL.standardizedFileURL.path,
                    within: standardizedRootPath
                ) else { continue }
                currentFilesInDir.insert(relativePath)
                modDates[relativePath] = values.contentModificationDate ?? Date.distantPast
            }
            
            // Remove files that were deleted from this directory
            let dirRelativePrefix = dir == standardizedRootPath ? "" : (Self.relativePath(of: dir, within: standardizedRootPath) ?? "") + "/"
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

    private static func isPath(_ path: String, within rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
    }

    static func shouldIgnoreCloudPlaceholder(
        at url: URL,
        resourceValues: URLResourceValues? = nil
    ) -> Bool {
        if resourceValues?.ubiquitousItemDownloadingStatus == .notDownloaded {
            return true
        }

        let fileName = url.lastPathComponent
        let pathExtension = url.pathExtension.lowercased()
        if (fileName.hasPrefix(".") && pathExtension == "icloud") || pathExtension == "cloud" {
            return true
        }

        if resourceValues?.fileSize == 0,
           getxattr(url.path, "com.dropbox.attrs", nil, 0, 0, 0) > 0 {
            return true
        }

        return false
    }

    private static func relativePath(of path: String, within rootPath: String) -> String? {
        guard isPath(path, within: rootPath) else { return nil }
        guard path != rootPath else { return "" }
        return String(path.dropFirst(rootPath.count + (rootPath.hasSuffix("/") ? 0 : 1)))
    }
    
    fileprivate func handleEvents(for folderId: UUID, changedPaths: Set<String>, requiresFullRescan: Bool, rootChanged: Bool) {
        lastEventTime[folderId] = Date()
        guard let folder = watchedFolders[folderId] else { return }
        guard folder.isEnabled else { return }
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

        if rootChanged {
            rootChangedFolders.insert(folderId)
        }
        
        debounceWorkItems[folderId]?.cancel()
        
        let workItem = DispatchWorkItem { [weak self] in
            self?.processChanges(for: folderId)
        }
        debounceWorkItems[folderId] = workItem
        let delay = max(debounceInterval, folder.triggerDelay)
        queue.asyncAfter(deadline: .now() + delay, execute: workItem)
    }
    
    private func processChanges(for folderId: UUID) {
        guard let folder = watchedFolders[folderId] else { return }
        guard !pausedFolders.contains(folderId) else { return }
        
        let previousModDates = fileModDates[folderId] ?? [:]
        
        let useFullRescan = forcedFullRescan.contains(folderId)
        let rootChanged = rootChangedFolders.contains(folderId)
        let changedPaths = pendingEventPaths[folderId] ?? []
        
        // Clear pending state
        pendingEventPaths.removeValue(forKey: folderId)
        forcedFullRescan.remove(folderId)
        rootChangedFolders.remove(folderId)

        if rootChanged {
            _ = reacquireAccessIfNeededSync(for: folder)
        }

        let path = resolvedURLs[folderId]?.path ?? folder.path
        guard isReadableDirectory(atPath: path) else {
            DebugLogger.log("Watcher root unavailable, preserving snapshot for: \(folder.name)")
            return
        }

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
        let disappearedFiles = previousSet.subtracting(currentSet)
        
        // Detect internal moves: when a file disappears from one location
        // and appears at another with the same name and modification date,
        // the user likely moved it intentionally within the watched folder.
        if !disappearedFiles.isEmpty {
            var disappearedLookup: [String: [Date]] = [:]
            for disappearedPath in disappearedFiles {
                let basename = (disappearedPath as NSString).lastPathComponent
                let modDate = previousModDates[disappearedPath] ?? .distantPast
                disappearedLookup[basename, default: []].append(modDate)
            }
            
            for newFile in brandNewFiles {
                let basename = (newFile as NSString).lastPathComponent
                let newModDate = modDates[newFile] ?? .distantPast
                if let candidates = disappearedLookup[basename],
                   candidates.contains(where: { abs($0.timeIntervalSince(newModDate)) < 2.0 }) {
                    DebugLogger.log("Skipping internal move: \(newFile)")
                    continue
                }
                genuineNewFiles.insert(newFile)
            }
        } else {
            genuineNewFiles.formUnion(brandNewFiles)
        }
        
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
        lastReconciliationTime[folderId] = Date()
        persistSnapshot(folderId: folderId, rootPath: path, modDates: newModDates)
        
        guard !genuineNewFiles.isEmpty else { return }
        
        DebugLogger.log("New/changed files detected in \(folder.name): \(genuineNewFiles)")
        
        let resolvedURL = resolvedURLs[folderId] ?? folder.url
        
        Task { @MainActor in
            self.delegate?.folderWatcher(self, didDetectChangesIn: folder, newFiles: genuineNewFiles, resolvedURL: resolvedURL)
        }
    }
    
    // Heartbeat to ensure streams stay alive (sometimes they can get stuck)
    private func startHeartbeatIfNeeded() {
        guard heartbeatTimer == nil, !watchedFolders.isEmpty else { return }

        heartbeatTimer = DispatchSource.makeTimerSource(queue: queue)
        heartbeatTimer?.schedule(deadline: .now() + heartbeatInterval, repeating: heartbeatInterval)
        heartbeatTimer?.setEventHandler { [weak self] in
            guard let self = self else { return }
            
            // Do a cheap health check regularly, and a full reconciliation only
            // occasionally to catch providers or volumes that drop FSEvents.
            for (id, folder) in Array(self.watchedFolders) {
                guard !self.pausedFolders.contains(id) else { continue }

                let path = self.resolvedURLs[id]?.path ?? folder.path
                guard self.isReadableDirectory(atPath: path) else {
                    DebugLogger.log("Heartbeat found unavailable watcher root: \(folder.name)")
                    _ = self.reacquireAccessIfNeededSync(for: folder)
                    continue
                }

                if self.streams[id] == nil {
                    DebugLogger.log("Heartbeat restarting missing stream for: \(folder.name)")
                    self.stopWatchingSync(id: id)
                    self.startWatchingSync(folder)
                    continue
                }

                let lastReconciliation = self.lastReconciliationTime[id] ?? self.streamStartTime[id] ?? Date.distantPast
                if Date().timeIntervalSince(lastReconciliation) >= self.reconciliationInterval {
                    DebugLogger.log("Heartbeat reconciliation for quiet watcher: \(folder.name)")
                    self.forcedFullRescan.insert(id)
                    self.processChanges(for: id)
                }
            }
        }
        heartbeatTimer?.resume()
    }

    private func stopHeartbeatIfIdle() {
        guard watchedFolders.isEmpty else { return }
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
    }

    private func performOnQueueSyncIfNeeded<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return block()
        } else {
            return queue.sync(execute: block)
        }
    }

    private func restorePersistedSnapshot(for folder: WatchedFolder, currentRootPath: String) -> Bool {
        guard let snapshot = readPersistedSnapshot(for: folder.id) else {
            return false
        }

        if snapshot.rootPath != currentRootPath, folder.bookmarkData == nil {
            removePersistedSnapshot(for: folder.id)
            return false
        }

        folderSnapshots[folder.id] = Set(snapshot.fileModDates.keys)
        fileModDates[folder.id] = snapshot.fileModDates
        lastReconciliationTime[folder.id] = snapshot.updatedAt
        DebugLogger.log("Restored watcher snapshot for \(folder.name) from previous session")
        return true
    }

    private func readPersistedSnapshot(for folderId: UUID) -> PersistedWatcherSnapshot? {
        guard let snapshotURL = persistedSnapshotURL(for: folderId),
              let data = try? Data(contentsOf: snapshotURL) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(PersistedWatcherSnapshot.self, from: data)
        } catch {
            DebugLogger.log("Discarding corrupt watcher snapshot for folder ID \(folderId): \(error)")
            removePersistedSnapshot(for: folderId)
            return nil
        }
    }

    private func persistSnapshot(folderId: UUID, rootPath: String, modDates: [String: Date]) {
        guard let snapshotURL = persistedSnapshotURL(for: folderId) else {
            return
        }

        do {
            let directory = snapshotURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

            let snapshot = PersistedWatcherSnapshot(rootPath: rootPath, fileModDates: modDates, updatedAt: Date())
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            DebugLogger.log("Failed to persist watcher snapshot for folder ID \(folderId): \(error)")
        }
    }

    private func removePersistedSnapshot(for folderId: UUID) {
        guard let snapshotURL = persistedSnapshotURL(for: folderId) else {
            return
        }

        do {
            if fileManager.fileExists(atPath: snapshotURL.path) {
                try fileManager.removeItem(at: snapshotURL)
            }
        } catch {
            DebugLogger.log("Failed to remove watcher snapshot for folder ID \(folderId): \(error)")
        }
    }

    private func persistedSnapshotURL(for folderId: UUID) -> URL? {
        snapshotStoreDirectory?.appendingPathComponent("\(folderId.uuidString).json")
    }
    
    // MARK: - Public Health & Recovery Methods
    
    /// Re-acquire security-scoped access if lost (e.g., volume disconnect)
    public func reacquireAccessIfNeeded(for folder: WatchedFolder) -> Bool {
        performOnQueueSyncIfNeeded {
            reacquireAccessIfNeededSync(for: folder)
        }
    }

    private func reacquireAccessIfNeededSync(for folder: WatchedFolder) -> Bool {
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
            if let oldURL = resolvedURLs[folder.id] {
                oldURL.stopAccessingSecurityScopedResource()
            }
            resolvedURLs[folder.id] = url
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
        let path = resolvedURL?.path ?? folder.path
        return isReadableDirectory(atPath: path)
    }
}

private struct PersistedWatcherSnapshot: Codable {
    let rootPath: String
    let fileModDates: [String: Date]
    let updatedAt: Date
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
    var rootChanged = false
    
    let cfPaths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    for i in 0..<numEvents {
        let flags = eventFlags[i]

        // Ignore file-system churn generated by Sorty itself.
        if flags & UInt32(kFSEventStreamEventFlagOwnEvent) != 0 {
            continue
        }
        
        if flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0 ||
            flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
            requiresFullRescan = true
        }

        if flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0 {
            rootChanged = true
        }
        
        if let cfPath = CFArrayGetValueAtIndex(cfPaths, i) {
            let path = Unmanaged<CFString>.fromOpaque(cfPath).takeUnretainedValue() as String
            changedPaths.insert(path)
        }
    }
    
    guard !changedPaths.isEmpty || requiresFullRescan else { return }
    watcher.handleEvents(for: folderId, changedPaths: changedPaths, requiresFullRescan: requiresFullRescan, rootChanged: rootChanged)
}

// Add extension to handle private method access in callback workaround if needed,
// but since callback is global, we exposed handleEvents as internal (default) or effectively internal.
// Since FolderWatcher is public, handleEvents needs to be accessible.
// We'll make handleEvents fileprivate and put callback in same file.

extension FolderWatcher {
    fileprivate func handleEventsPublicWrapper(for folderId: UUID, changedPaths: Set<String>, requiresFullRescan: Bool) {
        handleEvents(for: folderId, changedPaths: changedPaths, requiresFullRescan: requiresFullRescan, rootChanged: false)
    }
}
