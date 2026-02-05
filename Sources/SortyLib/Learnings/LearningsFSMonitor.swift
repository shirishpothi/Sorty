//
//  LearningsFSMonitor.swift
//  Sorty
//
//  FSEvents-based file system monitor for detecting manual file moves
//  after AI organization. Used to learn from user corrections.
//

import Foundation
import Combine

/// Snapshot of a directory's contents for detecting moves
// (Renamed to avoid conflict with WorkspaceHealth.DirectorySnapshot)
public struct FSSnapshot: Sendable {
    let files: Set<String>  // Full paths
    let timestamp: Date
    
    init(at url: URL) {
        var fileSet = Set<String>()
        if let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) {
            for case let fileURL as URL in enumerator {
                if let isFile = try? fileURL.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile, isFile {
                    fileSet.insert(fileURL.path)
                }
            }
        }
        self.files = fileSet
        self.timestamp = Date()
    }
}

/// Represents a detected file move
public struct DetectedFileMove: Sendable {
    public let fromPath: String
    public let toPath: String
    public let timestamp: Date
}

/// Thread-safe helper class for managing FSEventStream
/// This class is NOT MainActor-isolated and can be safely used from the event queue
private final class FSEventStreamManager: @unchecked Sendable {
    private var eventStream: FSEventStreamRef?
    private let eventQueue: DispatchQueue
    private weak var monitor: LearningsFSMonitor?
    
    init(eventQueue: DispatchQueue) {
        self.eventQueue = eventQueue
    }
    
    func setMonitor(_ monitor: LearningsFSMonitor) {
        self.monitor = monitor
    }
    
    func startStream(paths: [String]) {
        eventQueue.async { [weak self] in
            guard let self = self else { return }
            self.stopStreamSync()
            
            guard !paths.isEmpty else { return }
            
            let pathsToWatch = paths as CFArray
            
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            
            let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, eventFlags, _ in
                guard let info = info else { return }
                let manager = Unmanaged<FSEventStreamManager>.fromOpaque(info).takeUnretainedValue()
                
                guard let paths = unsafeBitCast(eventPaths, to: NSArray.self) as? [String] else { return }
                
                // Copy flags synchronously BEFORE escaping the callback to avoid dangling pointer
                let flagsCopy = Array(UnsafeBufferPointer(start: eventFlags, count: numEvents))
                
                // Dispatch to main actor
                DispatchQueue.main.async {
                    Task { @MainActor in
                        manager.monitor?.handleFSEvents(paths: paths, flags: flagsCopy)
                    }
                }
            }
            
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                pathsToWatch,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                1.0,  // Latency in seconds
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
            )
            
            if let stream = stream {
                self.eventStream = stream
                FSEventStreamSetDispatchQueue(stream, self.eventQueue)
                FSEventStreamStart(stream)
            }
        }
    }
    
    func stopStream() {
        eventQueue.sync { [weak self] in
            self?.stopStreamSync()
        }
    }
    
    private func stopStreamSync() {
        if let stream = eventStream {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            eventStream = nil
        }
    }
}

/// FSEvents-based monitor for detecting file moves in recently organized directories
@MainActor
public class LearningsFSMonitor: ObservableObject {
    
    // MARK: - Properties
    
    /// Directories being monitored with their snapshots
    private var monitoredDirectories: [URL: FSSnapshot] = [:]
    
    /// Cleanup timers for auto-removing monitoring after correlation window
    private var cleanupTasks: [URL: Task<Void, Never>] = [:]
    
    /// Stream manager (not MainActor isolated)
    private let streamManager: FSEventStreamManager
    
    /// Paths currently being watched
    private var watchedPaths: [String] = []
    
    /// Callback for detected file moves
    public var onFileMoveDetected: ((DetectedFileMove) -> Void)?
    
    /// Callback for files removed from monitored scope (moved outside or deleted)
    public var onFileRemoved: ((String) -> Void)?
    
    /// Correlation window in seconds (default 30 minutes)
    public var correlationWindowSeconds: TimeInterval = 30 * 60
    
    /// Minimum time between snapshot updates to avoid thrashing
    private let snapshotDebounceInterval: TimeInterval = 2.0
    private var pendingSnapshotUpdates: [URL: Task<Void, Never>] = [:]
    
    /// Queue for FSEvents callbacks
    private let eventQueue = DispatchQueue(label: "com.sorty.learnings.fsmonitor", qos: .utility)
    
    // MARK: - Initialization
    
    public init() {
        self.streamManager = FSEventStreamManager(eventQueue: eventQueue)
        self.streamManager.setMonitor(self)
    }
    
    deinit {
        // Stream cleanup is handled by FSEventStreamManager
    }
    
    // MARK: - Public API
    
    /// Start monitoring a directory for file moves
    public func startMonitoring(directory: URL) {
        guard !monitoredDirectories.keys.contains(directory) else {
            LogManager.shared.log("Already monitoring: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
            return
        }
        
        // Take initial snapshot
        let snapshot = FSSnapshot(at: directory)
        monitoredDirectories[directory] = snapshot
        
        LogManager.shared.log("Started monitoring: \(directory.lastPathComponent) (\(snapshot.files.count) files)", category: "LearningsFSMonitor")
        
        // Schedule automatic cleanup after correlation window
        scheduleCleanup(for: directory)
        
        // Restart FSEvents stream with new path
        watchedPaths = monitoredDirectories.keys.map { $0.path }
        streamManager.startStream(paths: watchedPaths)
    }
    
    /// Stop monitoring a specific directory
    public func stopMonitoring(directory: URL) {
        guard monitoredDirectories.keys.contains(directory) else { return }
        
        monitoredDirectories.removeValue(forKey: directory)
        cleanupTasks[directory]?.cancel()
        cleanupTasks.removeValue(forKey: directory)
        pendingSnapshotUpdates[directory]?.cancel()
        pendingSnapshotUpdates.removeValue(forKey: directory)
        
        LogManager.shared.log("Stopped monitoring: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
        
        // Restart FSEvents stream without this path
        if monitoredDirectories.isEmpty {
            streamManager.stopStream()
            watchedPaths = []
        } else {
            watchedPaths = monitoredDirectories.keys.map { $0.path }
            streamManager.startStream(paths: watchedPaths)
        }
    }
    
    /// Stop all monitoring
    public func stopAllMonitoring() {
        streamManager.stopStream()
        watchedPaths = []
        for task in cleanupTasks.values {
            task.cancel()
        }
        for task in pendingSnapshotUpdates.values {
            task.cancel()
        }
        monitoredDirectories.removeAll()
        cleanupTasks.removeAll()
        pendingSnapshotUpdates.removeAll()
    }
    
    /// Get list of currently monitored directories
    public var monitoredURLs: [URL] {
        Array(monitoredDirectories.keys)
    }
    
    // MARK: - Event Handling
    
    fileprivate func handleFSEvents(paths: [String], flags: [FSEventStreamEventFlags]) {
        // Debounce: schedule snapshot update for affected directories
        for path in paths {
            for (dirURL, _) in monitoredDirectories {
                if path.isSubpath(of: dirURL.path) {
                    scheduleSnapshotUpdate(for: dirURL)
                    break
                }
            }
        }
    }
    
    private func scheduleSnapshotUpdate(for directory: URL) {
        // Cancel any pending update for this directory
        pendingSnapshotUpdates[directory]?.cancel()
        
        // Schedule new update after debounce interval
        pendingSnapshotUpdates[directory] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(snapshotDebounceInterval * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            await self.updateSnapshotAndDetectMoves(for: directory)
        }
    }
    
    private func updateSnapshotAndDetectMoves(for directory: URL) async {
        guard let oldSnapshot = monitoredDirectories[directory] else { return }
        
        // Take new snapshot on background thread
        let newSnapshot = await Task.detached(priority: .utility) {
            FSSnapshot(at: directory)
        }.value
        
        // Detect moves by comparing snapshots
        let detection = detectFileMoves(from: oldSnapshot, to: newSnapshot, in: directory)
        
        // Update stored snapshot
        monitoredDirectories[directory] = newSnapshot
        
        // Notify about detected moves
        for move in detection.moves {
            LogManager.shared.log("Detected move: \(URL(fileURLWithPath: move.fromPath).lastPathComponent) → \(URL(fileURLWithPath: move.toPath).deletingLastPathComponent().lastPathComponent)/", category: "LearningsFSMonitor")
            onFileMoveDetected?(move)
        }
        
        // Notify about removed files (moved outside monitored scope or deleted)
        for removedPath in detection.removed {
            LogManager.shared.log("Detected removal: \(URL(fileURLWithPath: removedPath).lastPathComponent)", category: "LearningsFSMonitor")
            onFileRemoved?(removedPath)
        }
    }
    
    // MARK: - Move Detection
    
    /// Detect file moves by comparing snapshots
    /// Uses filename matching as a heuristic (could be enhanced with file hashes)
    private func detectFileMoves(from oldSnapshot: FSSnapshot, to newSnapshot: FSSnapshot, in directory: URL) -> (moves: [DetectedFileMove], removed: [String]) {
        var moves: [DetectedFileMove] = []
        var matchedRemoved: Set<String> = []
        var matchedAdded: Set<String> = []
        
        let removedFiles = oldSnapshot.files.subtracting(newSnapshot.files)
        let addedFiles = newSnapshot.files.subtracting(oldSnapshot.files)
        
        // For each removed file, see if a file with the same name appeared elsewhere
        for removedPath in removedFiles {
            let removedURL = URL(fileURLWithPath: removedPath)
            let fileName = removedURL.lastPathComponent
            
            // Look for the same filename in added files
            for addedPath in addedFiles {
                if matchedAdded.contains(addedPath) { continue }
                let addedURL = URL(fileURLWithPath: addedPath)
                if addedURL.lastPathComponent == fileName {
                    // Found a probable move
                    moves.append(DetectedFileMove(
                        fromPath: removedPath,
                        toPath: addedPath,
                        timestamp: Date()
                    ))
                    matchedRemoved.insert(removedPath)
                    matchedAdded.insert(addedPath)
                    break
                }
            }
        }
        
        let unmatchedRemoved = removedFiles.subtracting(matchedRemoved)
        return (moves, Array(unmatchedRemoved))
    }
    
    // MARK: - Cleanup
    
    private func scheduleCleanup(for directory: URL) {
        cleanupTasks[directory]?.cancel()
        
        cleanupTasks[directory] = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(correlationWindowSeconds * 1_000_000_000))
            guard !Task.isCancelled else { return }
            
            LogManager.shared.log("Correlation window expired for: \(directory.lastPathComponent)", category: "LearningsFSMonitor")
            self.stopMonitoring(directory: directory)
        }
    }
}
