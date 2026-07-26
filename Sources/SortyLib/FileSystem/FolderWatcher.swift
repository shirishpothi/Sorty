//
//  FolderWatcher.swift
//  Sorty
//
//  Scalable FSEvents monitoring for watched folders.
//

import CoreServices
import Foundation

/// Protocol for receiving bounded folder-change batches.
///
/// Returning `false` applies backpressure. `FolderWatcher` retains the batch,
/// pauses its event stream if necessary, and retries without growing an
/// unbounded in-memory queue.
@MainActor
public protocol FolderWatcherDelegate: AnyObject {
    @discardableResult
    func folderWatcher(
        _ watcher: FolderWatcher,
        didDetectChangesIn folder: WatchedFolder,
        newFiles: Set<String>,
        resolvedURL: URL
    ) -> Bool

    func folderWatcher(
        _ watcher: FolderWatcher,
        didDetectStaleBookmarkFor folder: WatchedFolder,
        newBookmarkData: Data
    )
}

/// Monitors directory hierarchies using one coalesced FSEvents stream.
///
/// All mutable state is isolated to `queue`. File enumeration is isolated to a
/// single utility queue, and delivery is bounded by the delegate's backpressure
/// response. This is why the type can safely cross actor boundaries.
public final class FolderWatcher: @unchecked Sendable {
    @MainActor public weak var delegate: FolderWatcherDelegate?

    private struct PersistedEventCursor: Codable {
        let eventID: FSEventStreamEventId
        let updatedAt: Date
    }

    struct ScaleSnapshot: Equatable, Sendable {
        let watchedFolderCount: Int
        let monitoringRootCount: Int
        let streamCount: Int
        let pendingFileCount: Int
        let activeScanCount: Int
        let trackedFileMetadataCount: Int
    }

    private static let maximumFilesPerBatch = 256
    private static let maximumPendingFiles = 4_096
    private static let eventCursorPersistenceDelay: TimeInterval = 5
    private static let streamLatency: TimeInterval = 1
    private static let retryDelay: TimeInterval = 0.25
    private static let healthCheckInterval: TimeInterval = 300
    private static let maximumExplicitRootsPerAnchor = 512
    private static let maximumPendingScans = 128

    private let queue = DispatchQueue(label: "com.sorty.folderwatcher", qos: .utility)
    private let scanQueue = DispatchQueue(label: "com.sorty.folderwatcher.scanner", qos: .utility)
    private let queueSpecificKey = DispatchSpecificKey<Void>()
    private let fileManager = FileManager.default

    private var stream: FSEventStreamRef?
    private var callbackContext: UnsafeMutableRawPointer?
    private var watchedFolders: [UUID: WatchedFolder] = [:]
    private var resolvedURLs: [UUID: URL] = [:]
    private var securityScopedFolderIDs: Set<UUID> = []
    private var folderIDsByRootPath: [String: [UUID]] = [:]
    private var sortedRootPaths: [String] = []
    private var monitoringRoots: [String] = []
    private var pausedFolders: Set<UUID> = []
    private var minimumEventIDs: [UUID: FSEventStreamEventId] = [:]
    private var exclusionMatcher = ExclusionMatcher.empty

    private var pendingFiles: [UUID: Set<String>] = [:]
    private var debounceWorkItems: [UUID: DispatchWorkItem] = [:]
    private var pendingFileCount = 0
    private var isSuspendedForBackpressure = false
    private var shouldReplayAfterBackpressure = false

    private var recentlyRemovedFiles: [UUID: [String: Date]] = [:]
    private var activeScanCount = 0
    private var activeScanPath: String?
    private var pendingScanPaths: [String] = []
    private var requiresFullRecoveryScan = false
    private var healthTimer: DispatchSourceTimer?
    private var cursorPersistenceWorkItem: DispatchWorkItem?
    private var persistedEventID: FSEventStreamEventId?
    private var latestProcessedEventID: FSEventStreamEventId?
    private var replayFromEventID: FSEventStreamEventId?
    private var hasCompletedInitialSync = false

    private lazy var watcherStateURL: URL? = {
        fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Sorty", isDirectory: true)
            .appendingPathComponent("WatcherState.json")
    }()

    public init() {
        queue.setSpecific(key: queueSpecificKey, value: ())
        persistedEventID = readPersistedEventCursor()?.eventID
        latestProcessedEventID = persistedEventID
        replayFromEventID = persistedEventID
    }

    deinit {
        performOnQueueSyncIfNeeded {
            stopStream()
            healthTimer?.cancel()
            healthTimer = nil
            cursorPersistenceWorkItem?.cancel()
            cursorPersistenceWorkItem = nil
        }
    }

    // MARK: - Public API

    /// Atomically replaces the immutable matcher used by the event and recovery
    /// scan pipelines. Pending batches are rechecked so a newly enabled rule
    /// takes effect before already-buffered files reach automation.
    public func updateExclusionMatcher(_ matcher: ExclusionMatcher) {
        queue.async { [weak self] in
            guard let self else { return }
            self.exclusionMatcher = matcher
            self.removeExcludedPendingFiles()
        }
    }

    /// Pauses one watched root without interrupting unrelated roots.
    public func pause(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pausedFolders.insert(folder.id)
            self.clearPendingFiles(for: folder.id)
            self.minimumEventIDs[folder.id] = FSEventsGetCurrentEventId()
            DebugLogger.log("Paused watching: \(folder.name)")
        }
    }

    /// Resumes from the current event cursor, intentionally ignoring changes
    /// made while Sorty owned the folder for a manual operation.
    public func resume(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self else { return }
            self.pausedFolders.remove(folder.id)
            self.clearPendingFiles(for: folder.id)
            self.minimumEventIDs[folder.id] = FSEventsGetCurrentEventId()
            DebugLogger.log("Resumed watching: \(folder.name)")
        }
    }

    /// Advances the root's baseline after known in-app mutations.
    ///
    /// Event IDs replace the old full hierarchy snapshot, so this remains O(1)
    /// even when a watched folder contains millions of files.
    public func refreshSnapshot(for folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self else { return }
            self.clearPendingFiles(for: folder.id)
            self.minimumEventIDs[folder.id] = FSEventsGetCurrentEventId()
            DebugLogger.log("Advanced watcher cursor: \(folder.name)")
        }
    }

    public func startWatching(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self, folder.isEnabled else { return }
            let previousRoots = self.monitoringRoots
            self.install(folder, minimumEventID: FSEventsGetCurrentEventId())
            self.rebuildPathIndex()
            if previousRoots != self.monitoringRoots {
                self.rebuildStream()
            }
            self.startHealthTimerIfNeeded()
        }
    }

    public func stopWatching(_ folder: WatchedFolder) {
        queue.async { [weak self] in
            guard let self else { return }
            let previousRoots = self.monitoringRoots
            self.uninstall(folderID: folder.id)
            self.rebuildPathIndex()
            if previousRoots != self.monitoringRoots {
                self.rebuildStream()
            }
            self.stopHealthTimerIfIdle()
        }
    }

    public func stopAllWatching() {
        performOnQueueSyncIfNeeded {
            stopStream()
            for folderID in securityScopedFolderIDs {
                resolvedURLs[folderID]?.stopAccessingSecurityScopedResource()
            }
            resolvedURLs.removeAll()
            securityScopedFolderIDs.removeAll()
            watchedFolders.removeAll()
            folderIDsByRootPath.removeAll()
            sortedRootPaths.removeAll()
            monitoringRoots.removeAll()
            pausedFolders.removeAll()
            minimumEventIDs.removeAll()
            clearAllPendingFiles()
            pendingScanPaths.removeAll()
            requiresFullRecoveryScan = false
            stopHealthTimerIfIdle()
        }
    }

    /// Applies a complete configuration snapshot with one index rebuild and at
    /// most one stream restart, regardless of the number of folders changed.
    public func syncWithFolders(_ folders: [WatchedFolder]) {
        queue.async { [weak self] in
            guard let self else { return }

            let enabledFolders = Dictionary(
                uniqueKeysWithValues: folders.lazy.filter(\.isEnabled).map { ($0.id, $0) }
            )
            let previousRoots = self.monitoringRoots
            let initialMinimumEventID = self.persistedEventID ?? FSEventsGetCurrentEventId()

            for folderID in Array(self.watchedFolders.keys) where enabledFolders[folderID] == nil {
                self.uninstall(folderID: folderID)
            }

            for folder in enabledFolders.values {
                if let existing = self.watchedFolders[folder.id],
                   existing.path == folder.path,
                   existing.bookmarkData == folder.bookmarkData {
                    self.watchedFolders[folder.id] = folder
                } else {
                    self.uninstall(folderID: folder.id)
                    self.install(
                        folder,
                        minimumEventID: self.hasCompletedInitialSync
                            ? FSEventsGetCurrentEventId()
                            : initialMinimumEventID
                    )
                }
            }

            self.hasCompletedInitialSync = true
            self.rebuildPathIndex()
            if previousRoots != self.monitoringRoots || self.stream == nil {
                self.rebuildStream()
            }
            self.startHealthTimerIfNeeded()
            self.stopHealthTimerIfIdle()
        }
    }

    public func reacquireAccessIfNeeded(for folder: WatchedFolder) -> Bool {
        performOnQueueSyncIfNeeded {
            guard watchedFolders[folder.id] != nil else { return false }
            return resolveBookmark(for: folder) != nil
        }
    }

    public func isFolderHealthy(_ folder: WatchedFolder) -> Bool {
        performOnQueueSyncIfNeeded {
            let path = resolvedURLs[folder.id]?.path ?? folder.path
            return isReadableDirectory(atPath: path)
        }
    }

    func scaleSnapshot() -> ScaleSnapshot {
        performOnQueueSyncIfNeeded {
            ScaleSnapshot(
                watchedFolderCount: watchedFolders.count,
                monitoringRootCount: monitoringRoots.count,
                streamCount: stream == nil ? 0 : 1,
                pendingFileCount: pendingFileCount,
                activeScanCount: activeScanCount,
                trackedFileMetadataCount: 0
            )
        }
    }

    // MARK: - Configuration and stream topology

    private func install(
        _ folder: WatchedFolder,
        minimumEventID: FSEventStreamEventId
    ) {
        watchedFolders[folder.id] = folder
        minimumEventIDs[folder.id] = minimumEventID
        _ = resolveBookmark(for: folder)
    }

    private func uninstall(folderID: UUID) {
        watchedFolders.removeValue(forKey: folderID)
        pausedFolders.remove(folderID)
        minimumEventIDs.removeValue(forKey: folderID)
        recentlyRemovedFiles.removeValue(forKey: folderID)
        clearPendingFiles(for: folderID)

        if let url = resolvedURLs.removeValue(forKey: folderID),
           securityScopedFolderIDs.remove(folderID) != nil {
            url.stopAccessingSecurityScopedResource()
        }
    }

    @discardableResult
    private func resolveBookmark(for folder: WatchedFolder) -> URL? {
        guard let bookmarkData = folder.bookmarkData else {
            return nil
        }

        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            DebugLogger.log("Failed to resolve bookmark for: \(folder.name)")
            return nil
        }

        if let previousURL = resolvedURLs.removeValue(forKey: folder.id),
           securityScopedFolderIDs.remove(folder.id) != nil {
            previousURL.stopAccessingSecurityScopedResource()
        }

        if !Self.requiresSecurityScopedAccess {
            resolvedURLs[folder.id] = url
        } else if url.startAccessingSecurityScopedResource() {
            resolvedURLs[folder.id] = url
            securityScopedFolderIDs.insert(folder.id)
        }

        if isStale,
           let newData = try? url.bookmarkData(
               options: .withSecurityScope,
               includingResourceValuesForKeys: nil,
               relativeTo: nil
           ) {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.delegate?.folderWatcher(
                    self,
                    didDetectStaleBookmarkFor: folder,
                    newBookmarkData: newData
                )
            }
        }

        return url
    }

    private func rebuildPathIndex() {
        var foldersByPath: [String: [UUID]] = [:]
        foldersByPath.reserveCapacity(watchedFolders.count)

        for (folderID, folder) in watchedFolders {
            let path = standardizedPath(resolvedURLs[folderID]?.path ?? folder.path)
            foldersByPath[path, default: []].append(folderID)
        }

        folderIDsByRootPath = foldersByPath
        sortedRootPaths = foldersByPath.keys.sorted()
        monitoringRoots = Self.coalescedMonitoringRoots(from: sortedRootPaths)
    }

    static func minimalMonitoringRoots(from paths: [String]) -> [String] {
        let uniquePaths = Set(paths.map { URL(fileURLWithPath: $0).standardizedFileURL.path })
        let orderedPaths = uniquePaths.sorted {
            let leftDepth = $0.split(separator: "/").count
            let rightDepth = $1.split(separator: "/").count
            return leftDepth == rightDepth ? $0 < $1 : leftDepth < rightDepth
        }

        var selected: [String] = []
        var selectedSet: Set<String> = []
        selected.reserveCapacity(orderedPaths.count)

        for path in orderedPaths {
            var ancestor = URL(fileURLWithPath: path).deletingLastPathComponent().path
            var isCovered = selectedSet.contains(path)

            while !isCovered, ancestor != "/", !ancestor.isEmpty {
                if selectedSet.contains(ancestor) {
                    isCovered = true
                    break
                }
                let parent = URL(fileURLWithPath: ancestor).deletingLastPathComponent().path
                if parent == ancestor { break }
                ancestor = parent
            }

            if !isCovered, selectedSet.contains("/") {
                isCovered = true
            }

            if !isCovered {
                selected.append(path)
                selectedSet.insert(path)
            }
        }

        return selected.sorted()
    }

    static func coalescedMonitoringRoots(from paths: [String]) -> [String] {
        var rootsByAnchor: [String: [String]] = [:]
        var collapsedAnchors: Set<String> = []

        for rawPath in paths {
            let root = URL(fileURLWithPath: rawPath).standardizedFileURL.path
            let anchor = monitoringAnchor(for: root)
            guard !collapsedAnchors.contains(anchor) else { continue }

            rootsByAnchor[anchor, default: []].append(root)
            if rootsByAnchor[anchor]?.count ?? 0 > maximumExplicitRootsPerAnchor, anchor != "/" {
                rootsByAnchor.removeValue(forKey: anchor)
                collapsedAnchors.insert(anchor)
            }
        }

        var candidates = Array(collapsedAnchors)
        candidates.reserveCapacity(
            collapsedAnchors.count + rootsByAnchor.values.reduce(0) { $0 + $1.count }
        )
        for roots in rootsByAnchor.values {
            candidates.append(contentsOf: roots)
        }
        return minimalMonitoringRoots(from: candidates)
    }

    private static func monitoringAnchor(for path: String) -> String {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard components.count > 2 else { return path }

        // Keep the anchor at a user, mounted-volume, or top-level data boundary.
        // This bounds the FSEvents path array without broadening a subscription
        // all the way to the startup disk root.
        if components[1] == "Users" || components[1] == "Volumes" {
            guard components.count > 3 else { return path }
            return NSString.path(withComponents: Array(components.prefix(3)))
        }
        return NSString.path(withComponents: Array(components.prefix(2)))
    }

    private func rebuildStream() {
        stopStream()
        guard !monitoringRoots.isEmpty, !isSuspendedForBackpressure else { return }

        let contextObject = FolderWatcherContext(watcher: self)
        let info = UnsafeMutableRawPointer(Unmanaged.passRetained(contextObject).toOpaque())
        var context = FSEventStreamContext(
            version: 0,
            info: info,
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let sinceWhen: FSEventStreamEventId
        if let replayFromEventID {
            sinceWhen = replayFromEventID
        } else {
            let currentEventID = FSEventsGetCurrentEventId()
            replayFromEventID = currentEventID
            sinceWhen = currentEventID
        }
        let flags = FSEventStreamCreateFlags(
            kFSEventStreamCreateFlagUseCFTypes |
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagWatchRoot |
            kFSEventStreamCreateFlagMarkSelf
        )

        guard let newStream = FSEventStreamCreate(
            kCFAllocatorDefault,
            folderWatcherCallback,
            &context,
            monitoringRoots as CFArray,
            sinceWhen,
            Self.streamLatency,
            flags
        ) else {
            Unmanaged<FolderWatcherContext>.fromOpaque(info).release()
            DebugLogger.log("FSEvents: Failed to create shared watched-folder stream")
            return
        }

        FSEventStreamSetDispatchQueue(newStream, queue)
        guard FSEventStreamStart(newStream) else {
            FSEventStreamInvalidate(newStream)
            FSEventStreamRelease(newStream)
            Unmanaged<FolderWatcherContext>.fromOpaque(info).release()
            DebugLogger.log("FSEvents: Failed to start shared watched-folder stream")
            return
        }

        stream = newStream
        callbackContext = info
        DebugLogger.log(
            "FSEvents: Watching \(watchedFolders.count) folders through \(monitoringRoots.count) coalesced roots"
        )
    }

    private func stopStream() {
        if let stream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            self.stream = nil
        }

        if let callbackContext {
            Unmanaged<FolderWatcherContext>.fromOpaque(callbackContext).release()
            self.callbackContext = nil
        }
    }

    // MARK: - Event routing

    fileprivate func handleEvent(
        path rawPath: String,
        flags: FSEventStreamEventFlags,
        eventID: FSEventStreamEventId
    ) -> Bool {
        guard !isSuspendedForBackpressure else { return false }
        if exclusionMatcher.needsRefresh() {
            exclusionMatcher = exclusionMatcher.refreshed()
        }
        if flags & UInt32(kFSEventStreamEventFlagOwnEvent) != 0 {
            latestProcessedEventID = max(latestProcessedEventID ?? eventID, eventID)
            scheduleCursorPersistence()
            return true
        }

        let path = standardizedPath(rawPath)
        let requiresRecursiveScan =
            flags & UInt32(kFSEventStreamEventFlagMustScanSubDirs) != 0
        let rootChanged =
            flags & UInt32(kFSEventStreamEventFlagRootChanged) != 0
        let directoryArrived =
            flags & UInt32(kFSEventStreamEventFlagItemIsDir) != 0 &&
            (
                flags & UInt32(kFSEventStreamEventFlagItemCreated) != 0 ||
                flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
            )
        let itemWasRenamed =
            flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0
        let eventHistoryIsUnsafe =
            flags & UInt32(kFSEventStreamEventFlagUserDropped) != 0 ||
            flags & UInt32(kFSEventStreamEventFlagKernelDropped) != 0 ||
            flags & UInt32(kFSEventStreamEventFlagEventIdsWrapped) != 0

        if eventHistoryIsUnsafe {
            scheduleRecoveryScans(affectedBy: path)
        } else if rootChanged {
            let recoveredRoots = reacquireRoots(affectedBy: path)
            for root in recoveredRoots {
                beginScan(at: root)
            }
        } else if itemWasRenamed, !fileManager.fileExists(atPath: path) {
            rememberRemoval(at: path)
        } else if requiresRecursiveScan || directoryArrived {
            let name = URL(fileURLWithPath: path).lastPathComponent
            if let folderID = mostSpecificFolderID(containing: path),
               itemWasRenamed,
               consumeRecentRemoval(named: name, folderID: folderID) {
                // A rename with both endpoints inside the same watched root is
                // a user move, not a new arrival.
            } else {
                scheduleDirectoryScan(at: path)
            }
        } else if flags & UInt32(kFSEventStreamEventFlagItemRemoved) != 0 {
            rememberRemoval(at: path)
        } else {
            enqueueFileIfActionable(at: path, flags: flags, eventID: eventID)
        }

        latestProcessedEventID = max(latestProcessedEventID ?? eventID, eventID)
        scheduleCursorPersistence()
        return !isSuspendedForBackpressure
    }

    private func enqueueFileIfActionable(
        at path: String,
        flags: FSEventStreamEventFlags,
        eventID: FSEventStreamEventId
    ) {
        guard let folderID = mostSpecificFolderID(containing: path),
              let folder = watchedFolders[folderID],
              !pausedFolders.contains(folderID),
              eventID >= minimumEventIDs[folderID] ?? 0 else {
            return
        }

        let rootPath = rootPath(for: folderID, folder: folder)
        guard let relativePath = Self.relativePath(of: path, within: rootPath),
              !relativePath.isEmpty,
              !Self.isIgnoredFile(URL(fileURLWithPath: path).lastPathComponent) else {
            return
        }

        let url = URL(fileURLWithPath: path)
        guard let values = try? url.resourceValues(forKeys: [
            .isRegularFileKey,
            .fileSizeKey,
            .creationDateKey,
            .contentModificationDateKey,
            .ubiquitousItemDownloadingStatusKey,
        ]),
        values.isRegularFile == true,
        !Self.shouldIgnoreCloudPlaceholder(at: url, resourceValues: values),
        !exclusionMatcher.shouldExcludeFile(
            at: url,
            size: Int64(values.fileSize ?? 0),
            creationDate: values.creationDate,
            modificationDate: values.contentModificationDate
        ) else {
            return
        }

        if flags & UInt32(kFSEventStreamEventFlagItemRenamed) != 0,
           consumeRecentRemoval(named: url.lastPathComponent, folderID: folderID) {
            return
        }

        enqueue(relativePath, for: folderID)
    }

    private func enqueue(_ relativePath: String, for folderID: UUID) {
        guard pendingFileCount < Self.maximumPendingFiles else {
            suspendForBackpressure()
            return
        }

        var files = pendingFiles[folderID] ?? []
        let wasInserted = files.insert(relativePath).inserted
        pendingFiles[folderID] = files
        if wasInserted {
            pendingFileCount += 1
        }

        if files.count >= Self.maximumFilesPerBatch {
            flushPendingFiles(for: folderID)
        } else {
            scheduleFlush(for: folderID)
        }
    }

    private func scheduleFlush(for folderID: UUID) {
        guard let folder = watchedFolders[folderID] else { return }
        debounceWorkItems[folderID]?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.flushPendingFiles(for: folderID)
        }
        debounceWorkItems[folderID] = workItem
        queue.asyncAfter(
            deadline: .now() + max(Self.retryDelay, folder.triggerDelay),
            execute: workItem
        )
    }

    private func flushPendingFiles(for folderID: UUID) {
        guard let folder = watchedFolders[folderID],
              !pausedFolders.contains(folderID),
              let files = pendingFiles[folderID],
              !files.isEmpty else {
            clearPendingFiles(for: folderID)
            return
        }

        let batch = Set(files.prefix(Self.maximumFilesPerBatch))
        let resolvedURL = resolvedURLs[folderID] ?? folder.url
        let watcher = self
        var accepted = false

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                accepted = delegate?.folderWatcher(
                    watcher,
                    didDetectChangesIn: folder,
                    newFiles: batch,
                    resolvedURL: resolvedURL
                ) ?? true
            }
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated {
                    accepted = delegate?.folderWatcher(
                        watcher,
                        didDetectChangesIn: folder,
                        newFiles: batch,
                        resolvedURL: resolvedURL
                    ) ?? true
                }
            }
        }

        guard accepted else {
            suspendForBackpressure()
            scheduleFlush(for: folderID)
            return
        }

        pendingFiles[folderID]?.subtract(batch)
        pendingFileCount -= batch.count
        if pendingFiles[folderID]?.isEmpty == true {
            pendingFiles.removeValue(forKey: folderID)
            debounceWorkItems.removeValue(forKey: folderID)
        } else {
            scheduleFlush(for: folderID)
        }

        resumeAfterBackpressureIfPossible()
        scheduleCursorPersistence()
    }

    private func suspendForBackpressure() {
        guard !isSuspendedForBackpressure else { return }
        isSuspendedForBackpressure = true
        shouldReplayAfterBackpressure = true
        cursorPersistenceWorkItem?.cancel()
        cursorPersistenceWorkItem = nil
        queue.async { [weak self] in
            self?.stopStream()
        }
        DebugLogger.log("FSEvents: Paused shared stream to apply bounded backpressure")
    }

    private func resumeAfterBackpressureIfPossible() {
        guard isSuspendedForBackpressure,
              pendingFileCount == 0,
              activeScanCount == 0 else {
            return
        }

        isSuspendedForBackpressure = false
        if shouldReplayAfterBackpressure {
            shouldReplayAfterBackpressure = false
            rebuildStream()
        }
    }

    private func rememberRemoval(at path: String) {
        guard let folderID = mostSpecificFolderID(containing: path) else { return }
        let name = URL(fileURLWithPath: path).lastPathComponent
        var removals = recentlyRemovedFiles[folderID] ?? [:]
        let cutoff = Date().addingTimeInterval(-3)
        removals = removals.filter { $0.value >= cutoff }
        if removals.count < 128 {
            removals[name] = Date()
        }
        recentlyRemovedFiles[folderID] = removals
    }

    private func consumeRecentRemoval(named name: String, folderID: UUID) -> Bool {
        guard var removals = recentlyRemovedFiles[folderID],
              let removedAt = removals.removeValue(forKey: name),
              Date().timeIntervalSince(removedAt) < 3 else {
            return false
        }
        recentlyRemovedFiles[folderID] = removals
        return true
    }

    // MARK: - Bounded scanning

    private func scheduleDirectoryScan(at path: String) {
        let scanPath: String
        if isReadableDirectory(atPath: path) {
            scanPath = path
        } else if let folderID = mostSpecificFolderID(containing: path),
                  let folder = watchedFolders[folderID] {
            scanPath = rootPath(for: folderID, folder: folder)
        } else {
            return
        }
        guard !exclusionMatcher.shouldPruneDirectory(
            at: URL(fileURLWithPath: scanPath)
        ) else {
            return
        }
        beginScan(at: scanPath)
    }

    private func scheduleRecoveryScans(affectedBy path: String) {
        let roots = watchedRootPaths(affectedBy: path)
        for root in roots where !exclusionMatcher.shouldPruneDirectory(
            at: URL(fileURLWithPath: root)
        ) {
            beginScan(at: root)
        }
    }

    private func reacquireRoots(affectedBy path: String) -> [String] {
        let previousMonitoringRoots = monitoringRoots
        var affectedFolderIDs: [UUID] = []
        for (folderID, folder) in watchedFolders {
            let folderRoot = rootPath(for: folderID, folder: folder)
            guard Self.isPath(path, within: folderRoot) ||
                  Self.isPath(folderRoot, within: path) else {
                continue
            }
            affectedFolderIDs.append(folderID)
            _ = resolveBookmark(for: folder)
        }
        rebuildPathIndex()
        if previousMonitoringRoots != monitoringRoots {
            queue.async { [weak self] in
                self?.rebuildStream()
            }
        }
        let recoveredRoots = affectedFolderIDs.compactMap { folderID -> String? in
            guard let folder = watchedFolders[folderID] else { return nil }
            return rootPath(for: folderID, folder: folder)
        }
        return Self.minimalMonitoringRoots(from: recoveredRoots)
    }

    private func beginScan(at path: String) {
        let path = standardizedPath(path)
        if let activeScanPath, Self.isPath(path, within: activeScanPath) {
            return
        }
        if pendingScanPaths.contains(where: { Self.isPath(path, within: $0) }) {
            return
        }

        pendingScanPaths.removeAll(where: { Self.isPath($0, within: path) })
        guard pendingScanPaths.count < Self.maximumPendingScans else {
            pendingScanPaths.removeAll(keepingCapacity: true)
            requiresFullRecoveryScan = true
            return
        }
        pendingScanPaths.append(path)
        startNextScanIfNeeded()
    }

    private func startNextScanIfNeeded() {
        guard activeScanPath == nil else { return }

        if pendingScanPaths.isEmpty, requiresFullRecoveryScan {
            pendingScanPaths = monitoringRoots
            requiresFullRecoveryScan = false
        }
        guard !pendingScanPaths.isEmpty else {
            activeScanCount = 0
            resumeAfterBackpressureIfPossible()
            scheduleCursorPersistence()
            return
        }

        let path = pendingScanPaths.removeFirst()
        let matcher = exclusionMatcher
        activeScanPath = path
        activeScanCount = 1
        scanQueue.async { [weak self] in
            guard let self else { return }
            self.enumerateFiles(at: path, exclusionMatcher: matcher)
            self.queue.async {
                self.activeScanPath = nil
                self.activeScanCount = 0
                self.startNextScanIfNeeded()
            }
        }
    }

    private func enumerateFiles(
        at path: String,
        exclusionMatcher: ExclusionMatcher
    ) {
        let manager = FileManager()
        guard let enumerator = manager.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return
        }

        var absolutePaths: [String] = []
        absolutePaths.reserveCapacity(Self.maximumFilesPerBatch)

        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .isDirectoryKey,
                .fileSizeKey,
                .creationDateKey,
                .contentModificationDateKey,
                .ubiquitousItemDownloadingStatusKey,
            ]) else {
                continue
            }

            if values.isDirectory == true {
                if Self.isIgnoredFile(fileURL.lastPathComponent)
                    || exclusionMatcher.shouldPruneDirectory(at: fileURL) {
                    enumerator.skipDescendants()
                }
                continue
            }

            guard !Self.isIgnoredFile(fileURL.lastPathComponent),
                  values.isRegularFile == true,
                  !Self.shouldIgnoreCloudPlaceholder(at: fileURL, resourceValues: values),
                  !exclusionMatcher.shouldExcludeFile(
                      at: fileURL,
                      size: Int64(values.fileSize ?? 0),
                      creationDate: values.creationDate,
                      modificationDate: values.contentModificationDate
                  ) else {
                continue
            }

            absolutePaths.append(fileURL.standardizedFileURL.path)
            if absolutePaths.count == Self.maximumFilesPerBatch {
                ingestScannedPathsWithBackpressure(absolutePaths)
                absolutePaths.removeAll(keepingCapacity: true)
            }
        }

        if !absolutePaths.isEmpty {
            ingestScannedPathsWithBackpressure(absolutePaths)
        }
    }

    private func ingestScannedPathsWithBackpressure(_ paths: [String]) {
        var didIngest = false
        while !didIngest {
            didIngest = performOnQueueSyncIfNeeded {
                guard !watchedFolders.isEmpty else { return true }
                guard pendingFileCount + paths.count <= Self.maximumPendingFiles else {
                    suspendForBackpressure()
                    return false
                }

                for path in paths {
                    guard let folderID = mostSpecificFolderID(containing: path),
                          let folder = watchedFolders[folderID],
                          !pausedFolders.contains(folderID),
                          let relativePath = Self.relativePath(
                              of: path,
                              within: rootPath(for: folderID, folder: folder)
                          ),
                          !relativePath.isEmpty else {
                        continue
                    }
                    enqueue(relativePath, for: folderID)
                }
                return true
            }

            if !didIngest {
                Thread.sleep(forTimeInterval: Self.retryDelay)
            }
        }
    }

    private func removeExcludedPendingFiles() {
        guard !exclusionMatcher.isEmpty else { return }

        for folderID in Array(pendingFiles.keys) {
            guard let relativePaths = pendingFiles[folderID] else { continue }
            guard let folder = watchedFolders[folderID] else {
                clearPendingFiles(for: folderID)
                continue
            }

            let rootURL = URL(fileURLWithPath: rootPath(for: folderID, folder: folder))
            let includedPaths = Set(relativePaths.lazy.filter { relativePath in
                let url = rootURL.appendingPathComponent(relativePath)
                guard let values = try? url.resourceValues(forKeys: [
                    .fileSizeKey,
                    .creationDateKey,
                    .contentModificationDateKey,
                ]) else {
                    return true
                }
                return !self.exclusionMatcher.shouldExcludeFile(
                    at: url,
                    size: Int64(values.fileSize ?? 0),
                    creationDate: values.creationDate,
                    modificationDate: values.contentModificationDate
                )
            })

            pendingFileCount -= relativePaths.count - includedPaths.count
            if includedPaths.isEmpty {
                pendingFiles.removeValue(forKey: folderID)
                debounceWorkItems[folderID]?.cancel()
                debounceWorkItems.removeValue(forKey: folderID)
            } else {
                pendingFiles[folderID] = includedPaths
            }
        }

        resumeAfterBackpressureIfPossible()
    }

    // MARK: - Path index

    private func mostSpecificFolderID(containing path: String) -> UUID? {
        var candidate = path
        while true {
            if let folderIDs = folderIDsByRootPath[candidate] {
                return folderIDs.first(where: { !pausedFolders.contains($0) })
            }
            guard candidate != "/" else { return nil }
            let parent = URL(fileURLWithPath: candidate).deletingLastPathComponent().path
            guard parent != candidate else { return nil }
            candidate = parent
        }
    }

    private func watchedRootPaths(affectedBy path: String) -> [String] {
        var results: [String] = []

        if let ownerID = mostSpecificFolderID(containing: path),
           let owner = watchedFolders[ownerID] {
            results.append(rootPath(for: ownerID, folder: owner))
        }

        let prefix = path == "/" ? "/" : path + "/"
        var index = sortedRootPaths.partitioningIndex { $0 >= prefix }
        while index < sortedRootPaths.count {
            let root = sortedRootPaths[index]
            guard root.hasPrefix(prefix) else { break }
            results.append(root)
            index += 1
        }

        return Self.minimalMonitoringRoots(from: results)
    }

    private func rootPath(for folderID: UUID, folder: WatchedFolder) -> String {
        standardizedPath(resolvedURLs[folderID]?.path ?? folder.path)
    }

    private func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }

    private static func isPath(_ path: String, within rootPath: String) -> Bool {
        path == rootPath || path.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    private static func relativePath(of path: String, within rootPath: String) -> String? {
        guard isPath(path, within: rootPath) else { return nil }
        guard path != rootPath else { return "" }
        return String(path.dropFirst(rootPath.count + (rootPath == "/" ? 0 : 1)))
    }

    // MARK: - Cursor persistence and health

    private func scheduleCursorPersistence() {
        guard !isSuspendedForBackpressure,
              activeScanCount == 0,
              pendingFileCount == 0,
              let latestProcessedEventID,
              latestProcessedEventID > (persistedEventID ?? 0) else {
            return
        }

        cursorPersistenceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistLatestEventCursor()
        }
        cursorPersistenceWorkItem = workItem
        queue.asyncAfter(
            deadline: .now() + Self.eventCursorPersistenceDelay,
            execute: workItem
        )
    }

    private func persistLatestEventCursor() {
        guard !isSuspendedForBackpressure,
              activeScanCount == 0,
              pendingFileCount == 0,
              let eventID = latestProcessedEventID,
              eventID > (persistedEventID ?? 0),
              let watcherStateURL else {
            return
        }

        do {
            try fileManager.createDirectory(
                at: watcherStateURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let cursor = PersistedEventCursor(eventID: eventID, updatedAt: Date())
            try JSONEncoder().encode(cursor).write(to: watcherStateURL, options: .atomic)
            persistedEventID = eventID
            replayFromEventID = eventID
        } catch {
            DebugLogger.log("Failed to persist watched-folder event cursor: \(error)")
        }
    }

    private func readPersistedEventCursor() -> PersistedEventCursor? {
        guard let watcherStateURL,
              let data = try? Data(contentsOf: watcherStateURL) else {
            return nil
        }
        return try? JSONDecoder().decode(PersistedEventCursor.self, from: data)
    }

    private func startHealthTimerIfNeeded() {
        guard healthTimer == nil, !watchedFolders.isEmpty else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(
            deadline: .now() + Self.healthCheckInterval,
            repeating: Self.healthCheckInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self else { return }
            if self.stream == nil, !self.isSuspendedForBackpressure {
                self.rebuildStream()
            }
        }
        timer.resume()
        healthTimer = timer
    }

    private func stopHealthTimerIfIdle() {
        guard watchedFolders.isEmpty else { return }
        healthTimer?.cancel()
        healthTimer = nil
    }

    // MARK: - Helpers

    private func clearPendingFiles(for folderID: UUID) {
        debounceWorkItems[folderID]?.cancel()
        debounceWorkItems.removeValue(forKey: folderID)
        if let files = pendingFiles.removeValue(forKey: folderID) {
            pendingFileCount -= files.count
        }
    }

    private func clearAllPendingFiles() {
        debounceWorkItems.values.forEach { $0.cancel() }
        debounceWorkItems.removeAll()
        pendingFiles.removeAll()
        pendingFileCount = 0
        isSuspendedForBackpressure = false
        shouldReplayAfterBackpressure = false
    }

    private func isReadableDirectory(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory)
            && isDirectory.boolValue
            && fileManager.isReadableFile(atPath: path)
    }

    private static func isIgnoredFile(_ name: String) -> Bool {
        if name.hasPrefix(".") { return true }
        if ["Thumbs.db", "desktop.ini"].contains(name) { return true }
        if name.hasSuffix("~") { return true }
        return ["tmp", "download", "partial", "crdownload", "part"]
            .contains((name as NSString).pathExtension.lowercased())
    }

    private static var requiresSecurityScopedAccess: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
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

    private func performOnQueueSyncIfNeeded<T>(_ block: () -> T) -> T {
        if DispatchQueue.getSpecific(key: queueSpecificKey) != nil {
            return block()
        }
        return queue.sync(execute: block)
    }
}

private final class FolderWatcherContext {
    weak var watcher: FolderWatcher?

    init(watcher: FolderWatcher) {
        self.watcher = watcher
    }
}

private func folderWatcherCallback(
    streamRef: ConstFSEventStreamRef,
    clientCallBackInfo: UnsafeMutableRawPointer?,
    numEvents: Int,
    eventPaths: UnsafeMutableRawPointer,
    eventFlags: UnsafePointer<FSEventStreamEventFlags>,
    eventIds: UnsafePointer<FSEventStreamEventId>
) {
    guard let clientCallBackInfo else { return }
    let context = Unmanaged<FolderWatcherContext>
        .fromOpaque(clientCallBackInfo)
        .takeUnretainedValue()
    guard let watcher = context.watcher else { return }

    let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
    for index in 0..<numEvents {
        guard let value = CFArrayGetValueAtIndex(paths, index) else { continue }
        let path = Unmanaged<CFString>.fromOpaque(value).takeUnretainedValue() as String
        if !watcher.handleEvent(
            path: path,
            flags: eventFlags[index],
            eventID: eventIds[index]
        ) {
            break
        }
    }
}

private extension Array where Element == String {
    func partitioningIndex(where predicate: (String) -> Bool) -> Int {
        var lowerBound = 0
        var upperBound = count
        while lowerBound < upperBound {
            let midpoint = lowerBound + (upperBound - lowerBound) / 2
            if predicate(self[midpoint]) {
                upperBound = midpoint
            } else {
                lowerBound = midpoint + 1
            }
        }
        return lowerBound
    }
}
